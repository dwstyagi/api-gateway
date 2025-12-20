# frozen_string_literal: true

# Redis Initializer for API Gateway
#
# Purpose: Configure Redis connection for rate limiting, API key storage, and caching
#
# Why Redis?
# - In-memory speed (microseconds vs milliseconds)
# - Atomic operations (INCR, DECR, Lua scripts)
# - TTL support (auto-expiring keys for rate limit windows)
# - Rich data structures (hashes, sorted sets, strings)
#
# Connection Pooling:
# - Pool size: 25 connections (handles concurrent requests)
# - Timeout: 5 seconds (fail fast if Redis is overwhelmed)
#
# Interview Talking Point:
# "Connection pooling prevents opening/closing connections for each request,
# which would add 10-50ms latency. We reuse connections from a pool."

require "redis"

# Redis connection configuration
REDIS_CONFIG = {
  url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"),
  # Timeout for Redis operations (seconds)
  timeout: ENV.fetch("REDIS_TIMEOUT", 5).to_i,
  # Reconnect attempts if connection is lost
  reconnect_attempts: 3
}

# Initialize global Redis connection
# Note: For production with high concurrency, consider using ConnectionPool gem
# For now, we use a simple single connection (Rails handles thread safety)
$redis = Redis.new(REDIS_CONFIG)

# Test the connection on initialization
begin
  $redis.ping
  Rails.logger.info "✅ Redis connected successfully: #{REDIS_CONFIG[:url]}"
rescue Redis::CannotConnectError => e
  Rails.logger.error "❌ Redis connection failed: #{e.message}"
  Rails.logger.error "⚠️  Rate limiting and API key validation will not work!"
  # In production, you might want to raise an exception here to prevent startup
  # raise "Redis connection required for API Gateway functionality"
end

# Helper method to safely execute Redis commands with error handling
# This implements the "fail-open" vs "fail-closed" pattern
def with_redis_failsafe(fail_mode: :open, &block)
  yield($redis)
rescue Redis::BaseError => e
  Rails.logger.error "Redis error: #{e.message}"

  case fail_mode
  when :open
    # Fail open: Allow request to proceed (use for non-critical features)
    Rails.logger.warn "Failing open - allowing request despite Redis error"
    nil
  when :closed
    # Fail closed: Reject request (use for critical security features)
    Rails.logger.error "Failing closed - rejecting request due to Redis error"
    raise e
  end
end
