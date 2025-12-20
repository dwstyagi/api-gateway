# frozen_string_literal: true

# Rate Limiter Factory
#
# Creates the appropriate rate limiter instance based on policy strategy
# Provides a unified interface for all rate limiting strategies

class RateLimiterFactory
  # Strategy to class mapping
  STRATEGY_MAP = {
    'token_bucket' => RateLimiters::TokenBucketRateLimiter,
    'sliding_window' => RateLimiters::SlidingWindowRateLimiter,
    'fixed_window' => RateLimiters::FixedWindowRateLimiter,
    'leaky_bucket' => RateLimiters::LeakyBucketRateLimiter,
    'concurrency' => RateLimiters::ConcurrencyRateLimiter
  }.freeze

  # Create rate limiter instance for given policy
  #
  # @param policy [RateLimitPolicy] The rate limit policy
  # @return [BaseRateLimiter] Instance of specific rate limiter
  # @raise [ArgumentError] If strategy is unknown
  def self.create(policy)
    limiter_class = STRATEGY_MAP[policy.strategy]

    raise ArgumentError, "Unknown rate limiting strategy: #{policy.strategy}" unless limiter_class

    limiter_class.new(policy)
  end

  # Get available strategies
  def self.available_strategies
    STRATEGY_MAP.keys
  end
end
