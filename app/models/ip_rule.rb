class IpRule < ApplicationRecord
  # Validations
  validates :ip_address, presence: true,
                         format: { with: /\A(?:[0-9]{1,3}\.){3}[0-9]{1,3}\z|^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}\z/,
                                   message: "must be a valid IPv4 or IPv6 address" }

  validates :rule_type, presence: true,
                        inclusion: { in: %w[block allow] }

  # Callbacks
  after_save :sync_to_redis
  after_destroy :remove_from_redis

  # Scopes
  scope :blocked, -> { where(rule_type: 'block') }
  scope :allowed, -> { where(rule_type: 'allow') }
  scope :auto_blocked, -> { where(auto_blocked: true) }
  scope :manual, -> { where(auto_blocked: false) }
  scope :active, -> { where('expires_at IS NULL OR expires_at > ?', Time.current) }
  scope :expired, -> { where('expires_at IS NOT NULL AND expires_at <= ?', Time.current) }

  # Check if IP is blocked
  def self.blocked?(ip_address)
    # Check Redis cache first for performance
    cached = $redis.get("blocked_ip:#{ip_address}")
    return cached == '1' if cached.present?

    # Fallback to database
    rule = active.blocked.find_by(ip_address: ip_address)
    blocked = rule.present?

    # Cache the result
    if blocked
      ttl = rule.expires_at ? (rule.expires_at.to_i - Time.current.to_i) : 86400
      $redis.setex("blocked_ip:#{ip_address}", ttl, '1')
    end

    blocked
  end

  # Check if IP is allowed (whitelist)
  def self.allowed?(ip_address)
    active.allowed.exists?(ip_address: ip_address)
  end

  # Auto-block an IP with reason and duration
  def self.auto_block!(ip_address, reason:, duration: 3600)
    expires_at = Time.current + duration.seconds

    create!(
      ip_address: ip_address,
      rule_type: 'block',
      reason: reason,
      auto_blocked: true,
      expires_at: expires_at
    )
  end

  # Check if rule is expired
  def expired?
    expires_at.present? && expires_at < Time.current
  end

  # Check if rule is still active
  def active?
    !expired?
  end

  # Extend expiration time
  def extend_expiration!(additional_seconds)
    return unless expires_at.present?

    update!(expires_at: expires_at + additional_seconds.seconds)
  end

  private

  def sync_to_redis
    return unless rule_type == 'block' && active?

    # Cache blocked IP in Redis
    if expires_at.present?
      ttl = (expires_at.to_i - Time.current.to_i)
      $redis.setex("blocked_ip:#{ip_address}", ttl, '1')
    else
      $redis.set("blocked_ip:#{ip_address}", '1')
    end
  end

  def remove_from_redis
    $redis.del("blocked_ip:#{ip_address}")
  end
end
