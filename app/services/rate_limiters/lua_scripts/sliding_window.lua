-- Sliding Window Counter Rate Limiter (Atomic Lua Script)
--
-- Algorithm: Combines previous and current window counts with weighted average
-- Use case: Most accurate rate limiting without memory overhead (CloudFlare/Kong use this)
--
-- KEYS[1] = Redis key for current window
-- KEYS[2] = Redis key for previous window
-- ARGV[1] = capacity (max requests per window)
-- ARGV[2] = window_seconds (size of time window)
-- ARGV[3] = current timestamp (seconds)
--
-- Returns: {allowed, requests_remaining, retry_after_ms}

local curr_key = KEYS[1]
local prev_key = KEYS[2]
local capacity = tonumber(ARGV[1])
local window_seconds = tonumber(ARGV[2])
local now = tonumber(ARGV[3])

-- Get counts from both windows
local curr_count = tonumber(redis.call('GET', curr_key) or '0')
local prev_count = tonumber(redis.call('GET', prev_key) or '0')

-- Calculate position within current window (0.0 to 1.0)
local window_start = math.floor(now / window_seconds) * window_seconds
local time_in_window = now - window_start
local window_progress = time_in_window / window_seconds

-- Weighted count: (1 - progress) * prev_window + curr_window
-- Example: 40% through window with prev=50, curr=30
--          estimated = (0.6 * 50) + 30 = 60 requests
local weighted_count = math.floor((1 - window_progress) * prev_count) + curr_count

-- Check if request should be allowed
if weighted_count < capacity then
  -- Allow request - increment current window
  local new_count = redis.call('INCR', curr_key)

  -- Set expiry to 2x window duration (need to keep previous window)
  redis.call('EXPIRE', curr_key, window_seconds * 2)

  local requests_remaining = capacity - weighted_count - 1
  return {1, requests_remaining, 0}
else
  -- Deny request - calculate retry time
  local next_window = window_start + window_seconds
  local retry_after_ms = math.ceil((next_window - now) * 1000)

  return {0, 0, retry_after_ms}
end
