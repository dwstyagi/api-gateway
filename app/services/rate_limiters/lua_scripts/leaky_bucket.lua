-- Leaky Bucket Rate Limiter (Atomic Lua Script)
--
-- Algorithm: Requests fill a bucket, which drains at constant rate
-- Use case: Smooths bursts to enforce strict constant output rate (traffic shaping)
-- Difference from Token Bucket: Leaky bucket smooths, Token bucket allows bursts
--
-- KEYS[1] = Redis key for this bucket
-- ARGV[1] = capacity (max queue size)
-- ARGV[2] = leak_rate (requests processed per second)
-- ARGV[3] = current timestamp (seconds with milliseconds)
-- ARGV[4] = TTL for the key (seconds)
--
-- Returns: {allowed, queue_size, retry_after_ms}

local key = KEYS[1]
local capacity = tonumber(ARGV[1])
local leak_rate = tonumber(ARGV[2])
local now = tonumber(ARGV[3])
local ttl = tonumber(ARGV[4])

-- Get current state
local bucket = redis.call('HMGET', key, 'queue_size', 'last_leak')
local queue_size = tonumber(bucket[1])
local last_leak = tonumber(bucket[2])

-- Initialize bucket if it doesn't exist
if queue_size == nil then
  queue_size = 0
  last_leak = now
end

-- Calculate how much leaked since last check
local time_elapsed = now - last_leak
local leaked = time_elapsed * leak_rate

-- Update queue size (can't go below 0)
queue_size = math.max(0, queue_size - leaked)
last_leak = now

-- Try to add request to queue
if queue_size < capacity then
  -- Allow request - add to queue
  queue_size = queue_size + 1

  -- Update Redis
  redis.call('HMSET', key, 'queue_size', queue_size, 'last_leak', last_leak)
  redis.call('EXPIRE', key, ttl)

  local remaining = capacity - queue_size
  return {1, math.floor(remaining), 0}
else
  -- Deny request - queue is full
  -- Calculate when space will be available
  local requests_to_process = queue_size - capacity + 1
  local retry_after_seconds = requests_to_process / leak_rate
  local retry_after_ms = math.ceil(retry_after_seconds * 1000)

  -- Update state even on failure
  redis.call('HMSET', key, 'queue_size', queue_size, 'last_leak', last_leak)
  redis.call('EXPIRE', key, ttl)

  return {0, 0, retry_after_ms}
end
