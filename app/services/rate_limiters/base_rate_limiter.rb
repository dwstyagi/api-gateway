# frozen_string_literal: true

module RateLimiters
  # Base Rate Limiter
  #
  # Provides common functionality for all rate limiting strategies:
  # - Lua script loading and caching (using Redis SCRIPT LOAD)
  # - Redis key generation
  # - Fail-open vs fail-closed error handling
  # - Result object structure
  #
  # Why Lua scripts?
  # - Atomic execution (no race conditions in distributed system)
  # - Single round-trip to Redis (faster than multiple commands)
  # - Server-side execution (reduces network overhead)

  class BaseRateLimiter
    # Result object returned by all rate limiters
    RateLimitResult = Struct.new(:allowed, :remaining, :retry_after_ms, :error) do
      def allowed?
        allowed == true
      end

      def retry_after_seconds
        (retry_after_ms || 0) / 1000.0
      end
    end

    attr_reader :policy, :failure_mode

    def initialize(policy)
      @policy = policy
      @failure_mode = policy.redis_failure_mode
      @lua_sha = nil
    end

    # Check if request should be allowed
    # Returns RateLimitResult
    def check_limit(identifier)
      raise NotImplementedError, 'Subclasses must implement check_limit'
    end

    protected

    # Load Lua script into Redis and cache SHA
    # Scripts are loaded once and reused via SHA (more efficient)
    def load_script
      return @lua_sha if @lua_sha

      script_content = File.read(script_path)
      @lua_sha = $redis.script(:load, script_content)
    rescue Redis::BaseError => e
      handle_redis_error(e)
    end

    # Execute Lua script with SHA (fallback to EVAL if script not cached)
    def eval_script(keys:, argv:)
      sha = load_script
      $redis.evalsha(sha, keys: keys, argv: argv)
    rescue Redis::CommandError => e
      # Script not found in Redis cache - reload it
      if e.message.include?('NOSCRIPT')
        @lua_sha = nil
        sha = load_script
        $redis.evalsha(sha, keys: keys, argv: argv)
      else
        raise
      end
    rescue Redis::BaseError => e
      handle_redis_error(e)
    end

    # Generate Redis key for rate limiting
    # Format: ratelimit:{strategy}:{api_id}:{tier}:{identifier}:{suffix}
    #
    # Examples:
    #   ratelimit:token_bucket:123:pro:user:456
    #   ratelimit:sliding_window:789:free:apikey:abc:1234567890
    def redis_key(identifier, suffix: nil)
      strategy = self.class.name.demodulize.underscore.gsub('_rate_limiter', '')
      api_id = policy.api_definition_id
      tier = policy.tier || 'default'

      key = "ratelimit:#{strategy}:#{api_id}:#{tier}:#{identifier}"
      key += ":#{suffix}" if suffix
      key
    end

    # Handle Redis errors based on fail-open vs fail-closed mode
    #
    # Fail-open: Allow requests when Redis is down (availability over correctness)
    # Fail-closed: Deny requests when Redis is down (correctness over availability)
    #
    # When to use each:
    # - Fail-open: Public APIs, user-facing features (better UX)
    # - Fail-closed: Admin endpoints, critical operations (better security)
    def handle_redis_error(error)
      Rails.logger.error("Rate limiter Redis error: #{error.message}")

      if failure_mode == 'open'
        # Fail-open: Allow request but log error
        RateLimitResult.new(true, nil, 0, error.message)
      else
        # Fail-closed: Deny request
        RateLimitResult.new(false, 0, 5000, error.message)
      end
    end

    # Path to Lua script file
    def script_path
      raise NotImplementedError, 'Subclasses must implement script_path'
    end

    # Current timestamp (can be overridden for testing)
    def current_time
      Time.now.to_f
    end
  end
end
