# frozen_string_literal: true

module RateLimiters
  # Concurrency Limiter
  #
  # Algorithm:
  # - Limits active/concurrent requests (not requests per time)
  # - Increment counter on request start
  # - Decrement counter on request finish
  # - Reject if counter >= capacity
  #
  # Use cases:
  # - Protect backend services from overload
  # - Database connection pooling (max concurrent queries)
  # - Thread pool management
  # - Prevent resource exhaustion
  #
  # Different from rate limiting:
  #   Rate limiting: "Max 100 requests per minute"
  #   Concurrency limiting: "Max 100 requests in-flight at the same time"
  #
  # Example:
  #   Capacity: 50 concurrent requests
  #   - 50 slow requests arrive (take 10 seconds each)
  #   - Counter = 50 (at capacity)
  #   - New request arrives → rejected
  #   - One request finishes → counter = 49
  #   - New request arrives → allowed
  #
  # Important:
  #   Must call release() when request finishes (use ensure block)
  #   Failure to release causes "leak" - counter never decrements
  #
  # Configuration:
  #   capacity: Maximum concurrent requests

  class ConcurrencyRateLimiter < BaseRateLimiter
    # Acquire a concurrency slot
    def check_limit(identifier)
      acquire(identifier)
    end

    # Acquire a slot for concurrent request
    def acquire(identifier)
      keys = [redis_key(identifier)]
      argv = [
        policy.capacity,      # ARGV[1]
        'acquire',            # ARGV[2]
        ttl                   # ARGV[3]
      ]

      result = eval_script(keys: keys, argv: argv)

      # Lua returns: {allowed, current_count, retry_after_ms}
      allowed = result[0] == 1
      current_count = result[1]
      retry_after_ms = result[2]

      # Remaining = capacity - current_count
      remaining = policy.capacity - current_count

      RateLimitResult.new(allowed, remaining, retry_after_ms, nil)
    rescue Redis::BaseError => e
      handle_redis_error(e)
    end

    # Release a slot after request finishes
    # IMPORTANT: Must be called in ensure block
    def release(identifier)
      keys = [redis_key(identifier)]
      argv = [
        policy.capacity,      # ARGV[1]
        'release',            # ARGV[2]
        ttl                   # ARGV[3]
      ]

      result = eval_script(keys: keys, argv: argv)

      # Lua returns: {1, current_count, 0}
      current_count = result[1]
      remaining = policy.capacity - current_count

      RateLimitResult.new(true, remaining, 0, nil)
    rescue Redis::BaseError => e
      # On release failure, log but don't block
      Rails.logger.error("Failed to release concurrency slot: #{e.message}")
      RateLimitResult.new(true, nil, 0, e.message)
    end

    protected

    def script_path
      Rails.root.join('app/services/rate_limiters/lua_scripts/concurrency.lua')
    end

    # TTL for Redis key
    # Set to reasonable timeout (e.g., 1 hour) to auto-cleanup leaked slots
    def ttl
      3600 # 1 hour
    end
  end
end
