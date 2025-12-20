-- Token Bucket Rate Limiter (Atomic Lua Script)
--
-- Algorithm: Tokens refill at a constant rate. Each request consumes 1 token.
-- Use case: Allows bursts while maintaining average rate (e.g., API with burst traffic)
--
-- KEYS[1] = Redis key for this bucket (e.g., "ratelimit:token_bucket:user:123:endpoint:/api/orders")
-- ARGV[1] = capacity (max tokens in bucket)
-- ARGV[2] = refill_rate (tokens added per second)
-- ARGV[3] = current timestamp (seconds)
-- ARGV[4] = TTL for the key (seconds)
--
-- Returns: {allowed, tokens_remaining, retry_after_ms}
--   allowed = 1 (request allowed) or 0 (rate limited)
--   tokens_remaining = current token count
--   retry_after_ms = milliseconds until next token available (0 if allowed)

local key = KEYS[1]
local capacity = tonumber(ARGV[1])
local refill_rate = tonumber(ARGV[2])
local now = tonumber(ARGV[3])
local ttl = tonumber(ARGV[4])

-- Get current state from Redis
local bucket = redis.call('HMGET', key, 'tokens', 'last_refill')
local tokens = tonumber(bucket[1])
local last_refill = tonumber(bucket[2])

-- Initialize bucket if it doesn't exist
if tokens == nil then
  tokens = capacity
  last_refill = now
end

-- Calculate tokens to add based on time elapsed
local time_elapsed = now - last_refill
local tokens_to_add = time_elapsed * refill_rate

-- Refill bucket (capped at capacity)
tokens = math.min(capacity, tokens + tokens_to_add)
last_refill = now

-- Try to consume 1 token
if tokens >= 1 then
  -- Request allowed
  tokens = tokens - 1

  -- Update Redis
  redis.call('HMSET', key, 'tokens', tokens, 'last_refill', last_refill)
  redis.call('EXPIRE', key, ttl)

  return {1, math.floor(tokens), 0}
else
  -- Request denied - calculate retry_after
  local tokens_needed = 1 - tokens
  local retry_after_seconds = tokens_needed / refill_rate
  local retry_after_ms = math.ceil(retry_after_seconds * 1000)

  -- Update last_refill time even on failure
  redis.call('HMSET', key, 'tokens', tokens, 'last_refill', last_refill)
  redis.call('EXPIRE', key, ttl)

  return {0, math.floor(tokens), retry_after_ms}
end
