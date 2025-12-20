-- Fixed Window Counter Rate Limiter (Atomic Lua Script)
--
-- Algorithm: Count requests in fixed time windows
-- Use case: Simplest implementation, good for caching quotas (e.g., daily API limits)
-- Limitation: "Burst at boundary" problem - can get 2x limit by timing at window edges
--
-- KEYS[1] = Redis key for this window
-- ARGV[1] = capacity (max requests per window)
-- ARGV[2] = window_seconds (size of time window)
-- ARGV[3] = current timestamp (seconds)
--
-- Returns: {allowed, requests_remaining, retry_after_ms}

local key = KEYS[1]
local capacity = tonumber(ARGV[1])
local window_seconds = tonumber(ARGV[2])
local now = tonumber(ARGV[3])

-- Get current count
local count = tonumber(redis.call('GET', key) or '0')

-- Check if request should be allowed
if count < capacity then
  -- Allow request - increment counter
  local new_count = redis.call('INCR', key)

  -- Set expiry on first request in window
  if new_count == 1 then
    redis.call('EXPIRE', key, window_seconds)
  end

  local requests_remaining = capacity - new_count
  return {1, requests_remaining, 0}
else
  -- Deny request - calculate retry time
  local ttl = redis.call('TTL', key)
  local retry_after_ms = ttl > 0 and (ttl * 1000) or (window_seconds * 1000)

  return {0, 0, retry_after_ms}
end
