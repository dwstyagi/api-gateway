# frozen_string_literal: true

module RateLimiters
  # Token Bucket Rate Limiter
  #
  # Algorithm:
  # - Tokens refill at constant rate (refill_rate per second)
  # - Each request consumes 1 token
  # - Bucket has maximum capacity
  # - Allows bursts while maintaining average rate
  #
  # Use cases:
  # - API with burst traffic patterns
  # - User-facing features (better UX than strict rate limiting)
  # - Most common rate limiting algorithm
  #
  # Example:
  #   Capacity: 100, Refill rate: 10/sec
  #   - User makes 100 requests instantly (uses all tokens)
  #   - After 5 seconds, 50 tokens refilled
  #   - User can make 50 more requests
  #
  # Configuration:
  #   capacity: Maximum tokens in bucket
  #   refill_rate: Tokens added per second

  class TokenBucketRateLimiter < BaseRateLimiter
    def check_limit(identifier)
      keys = [redis_key(identifier)]
      argv = [
        policy.capacity,           # ARGV[1]
        policy.refill_rate,        # ARGV[2]
        current_time,              # ARGV[3]
        ttl                        # ARGV[4]
      ]

      result = eval_script(keys: keys, argv: argv)

      # Lua returns: {allowed, tokens_remaining, retry_after_ms}
      allowed = result[0] == 1
      remaining = result[1]
      retry_after_ms = result[2]

      RateLimitResult.new(allowed, remaining, retry_after_ms, nil)
    rescue Redis::BaseError => e
      handle_redis_error(e)
    end

    protected

    def script_path
      Rails.root.join('app/services/rate_limiters/lua_scripts/token_bucket.lua')
    end

    # TTL for Redis key (auto-cleanup inactive keys)
    # Set to 2x the time needed to fully refill bucket
    def ttl
      (policy.capacity / policy.refill_rate * 2).ceil
    end
  end
end
