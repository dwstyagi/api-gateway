# frozen_string_literal: true

module RateLimiters
  # Leaky Bucket Rate Limiter
  #
  # Algorithm:
  # - Requests fill a bucket (queue)
  # - Bucket drains/leaks at constant rate
  # - If bucket overflows (exceeds capacity), request is rejected
  # - Enforces strict constant output rate
  #
  # Use cases:
  # - Traffic shaping (smooth bursts to constant rate)
  # - Network routers and switches
  # - Video streaming (constant bitrate)
  # - When you want guaranteed constant rate (no bursts allowed)
  #
  # Token Bucket vs Leaky Bucket:
  #   Token Bucket:
  #     - Allows bursts (tokens accumulate when idle)
  #     - Better for APIs (allows legitimate bursts)
  #     - Example: User idle for 10 min, then makes 100 requests → allowed
  #
  #   Leaky Bucket:
  #     - Smooths bursts (strict constant output)
  #     - Better for traffic shaping
  #     - Example: User idle for 10 min, then makes 100 requests → queued/rejected
  #
  # Example:
  #   Capacity: 50 requests, Leak rate: 10 req/sec
  #   - 100 requests arrive instantly
  #   - First 50 fill the bucket (allowed)
  #   - Next 50 rejected (bucket full)
  #   - Bucket drains at 10 req/sec
  #   - After 5 seconds, bucket empty, can accept 50 more
  #
  # Configuration:
  #   capacity: Maximum queue size
  #   refill_rate: Used as leak_rate (requests processed per second)

  class LeakyBucketRateLimiter < BaseRateLimiter
    def check_limit(identifier)
      keys = [redis_key(identifier)]
      argv = [
        policy.capacity,           # ARGV[1]
        policy.refill_rate,        # ARGV[2] (used as leak_rate)
        current_time,              # ARGV[3]
        ttl                        # ARGV[4]
      ]

      result = eval_script(keys: keys, argv: argv)

      # Lua returns: {allowed, queue_size, retry_after_ms}
      allowed = result[0] == 1
      queue_size = result[1]
      retry_after_ms = result[2]

      RateLimitResult.new(allowed, queue_size, retry_after_ms, nil)
    rescue Redis::BaseError => e
      handle_redis_error(e)
    end

    protected

    def script_path
      Rails.root.join('app/services/rate_limiters/lua_scripts/leaky_bucket.lua')
    end

    # TTL for Redis key
    # Set to time needed to drain full bucket
    def ttl
      (policy.capacity / policy.refill_rate * 2).ceil
    end
  end
end
