-- Concurrency Limiter (Atomic Lua Script)
--
-- Algorithm: Limits concurrent/active requests (not requests per time)
-- Use case: Protect backends from overload (e.g., max concurrent DB connections)
-- Different from rate limiting: limits in-flight requests, not requests/second
--
-- KEYS[1] = Redis key for concurrency counter
-- ARGV[1] = capacity (max concurrent requests)
-- ARGV[2] = operation ('acquire' or 'release')
-- ARGV[3] = TTL for the key (seconds)
--
-- Returns:
--   For 'acquire': {allowed, current_count, retry_after_ms}
--   For 'release': {1, current_count, 0}

local key = KEYS[1]
local capacity = tonumber(ARGV[1])
local operation = ARGV[2]
local ttl = tonumber(ARGV[3])

-- Get current count
local count = tonumber(redis.call('GET', key) or '0')

if operation == 'acquire' then
  -- Try to acquire a slot
  if count < capacity then
    -- Allow request - increment counter
    local new_count = redis.call('INCR', key)
    redis.call('EXPIRE', key, ttl)

    return {1, new_count, 0}
  else
    -- Deny request - at capacity
    -- For concurrency, retry_after is unpredictable (depends on when other requests finish)
    -- Return a small default (e.g., 100ms for client to retry)
    return {0, count, 100}
  end
elseif operation == 'release' then
  -- Release a slot - decrement counter (never go below 0)
  if count > 0 then
    local new_count = redis.call('DECR', key)
    redis.call('EXPIRE', key, ttl)
    return {1, new_count, 0}
  else
    -- Already at 0, nothing to release
    return {1, 0, 0}
  end
else
  error('Invalid operation: must be "acquire" or "release"')
end
