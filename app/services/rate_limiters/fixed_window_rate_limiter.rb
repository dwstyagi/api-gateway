# frozen_string_literal: true

module RateLimiters
  # Fixed Window Counter Rate Limiter
  #
  # Algorithm:
  # - Count requests in fixed time windows
  # - Window resets at fixed intervals (e.g., every 60 seconds)
  # - Simplest rate limiting algorithm
  #
  # Use cases:
  # - Daily/hourly quota systems (e.g., "1000 requests per day")
  # - Simple caching scenarios where precision doesn't matter
  # - When implementation simplicity is more important than accuracy
  #
  # Limitation: "Burst at boundary" problem
  #   Example: 100 req/min limit
  #     12:00:59 - make 100 requests (allowed)
  #     12:01:00 - make 100 requests (allowed)
  #     Result: 200 requests in 2 seconds!
  #
  #   Why this happens:
  #     - Windows are: [12:00:00-12:01:00], [12:01:00-12:02:00]
  #     - Each window is independent
  #     - No consideration of previous window's traffic
  #
  # Solution: Use Sliding Window instead for accurate rate limiting
  #
  # Configuration:
  #   capacity: Maximum requests per window
  #   window_seconds: Size of time window

  class FixedWindowRateLimiter < BaseRateLimiter
    def check_limit(identifier)
      now = current_time
      window_seconds = policy.window_seconds

      # Calculate current window start time
      window_start = (now.to_i / window_seconds) * window_seconds

      # Redis key includes window start to create separate windows
      key = redis_key(identifier, suffix: window_start)

      keys = [key]
      argv = [
        policy.capacity,      # ARGV[1]
        window_seconds,       # ARGV[2]
        now                   # ARGV[3]
      ]

      result = eval_script(keys: keys, argv: argv)

      # Lua returns: {allowed, requests_remaining, retry_after_ms}
      allowed = result[0] == 1
      remaining = result[1]
      retry_after_ms = result[2]

      RateLimitResult.new(allowed, remaining, retry_after_ms, nil)
    rescue Redis::BaseError => e
      handle_redis_error(e)
    end

    protected

    def script_path
      Rails.root.join('app/services/rate_limiters/lua_scripts/fixed_window.lua')
    end
  end
end
