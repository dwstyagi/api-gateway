class RateLimitPolicy < ApplicationRecord
  # Associations
  belongs_to :api_definition

  # Validations
  validates :strategy, presence: true,
                       inclusion: { in: %w[token_bucket fixed_window sliding_window leaky_bucket concurrency] }

  validates :capacity, presence: true,
                       numericality: { only_integer: true, greater_than: 0 }

  validates :redis_failure_mode, presence: true,
                                 inclusion: { in: %w[open closed] }

  validate :validate_strategy_params

  # Ensure only one policy per (api_definition, tier) combination
  validates :tier, uniqueness: { scope: :api_definition_id, allow_nil: true }

  # Callbacks
  after_save :sync_to_redis
  after_destroy :remove_from_redis

  # Scopes
  scope :for_api, ->(api_id) { where(api_definition_id: api_id) }
  scope :for_tier, ->(tier) { where(tier: tier) }
  scope :default_policies, -> { where(tier: nil) }

  # Get policy configuration as hash
  def to_config
    {
      strategy: strategy,
      capacity: capacity,
      refill_rate: refill_rate,
      window_seconds: window_seconds,
      redis_failure_mode: redis_failure_mode
    }
  end

  # Check if this is a default policy (applies to all tiers)
  def default?
    tier.nil?
  end

  private

  def validate_strategy_params
    case strategy
    when 'token_bucket', 'leaky_bucket'
      if refill_rate.blank? || refill_rate <= 0
        errors.add(:refill_rate, "must be present and greater than 0 for #{strategy} strategy")
      end
    when 'fixed_window', 'sliding_window'
      if window_seconds.blank? || window_seconds <= 0
        errors.add(:window_seconds, "must be present and greater than 0 for #{strategy} strategy")
      end
    when 'concurrency'
      # Concurrency only needs capacity
    end
  end

  def sync_to_redis
    # Cache policy in Redis for fast lookups
    # Key format: policy:{api_definition_id}:{tier}
    tier_key = tier || 'default'
    redis_key = "policy:#{api_definition_id}:#{tier_key}"

    # Filter out nil values (Redis doesn't accept nil)
    config = to_config.compact
    $redis.hset(redis_key, config) if config.any?
  end

  def remove_from_redis
    tier_key = tier || 'default'
    redis_key = "policy:#{api_definition_id}:#{tier_key}"
    $redis.del(redis_key)
  end
end
