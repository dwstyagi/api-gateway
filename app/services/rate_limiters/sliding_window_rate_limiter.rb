# frozen_string_literal: true

module RateLimiters
  # Sliding Window Counter Rate Limiter
  #
  # Algorithm:
  # - Combines counts from current and previous windows
  # - Weighted average based on position in current window
  # - More accurate than fixed window, less memory than true sliding log
  #
  # Use cases:
  # - Production APIs (CloudFlare, Kong, Stripe use this)
  # - When you need accuracy without memory overhead
  # - Prevents "burst at boundary" problem of fixed window
  #
  # Example:
  #   Window: 60 seconds, Capacity: 100 requests
  #   Current time: 12:00:40 (40 seconds into window starting at 12:00:00)
  #   Previous window (11:59:00-12:00:00): 50 requests
  #   Current window (12:00:00-12:01:00): 30 requests
  #
  #   Calculation:
  #     progress = 40/60 = 0.667 (66.7% through window)
  #     estimated = (1 - 0.667) * 50 + 30 = 16.65 + 30 = 46.65 ≈ 46 requests
  #     remaining = 100 - 46 = 54 requests
  #
  # Configuration:
  #   capacity: Maximum requests per window
  #   window_seconds: Size of time window

  class SlidingWindowRateLimiter < BaseRateLimiter
    def check_limit(identifier)
      now = current_time
      window_seconds = policy.window_seconds

      # Calculate window boundaries
      current_window_start = (now.to_i / window_seconds) * window_seconds
      previous_window_start = current_window_start - window_seconds

      # Redis keys for current and previous windows
      curr_key = redis_key(identifier, suffix: current_window_start)
      prev_key = redis_key(identifier, suffix: previous_window_start)

      keys = [curr_key, prev_key]
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
      Rails.root.join('app/services/rate_limiters/lua_scripts/sliding_window.lua')
    end
  end
end
