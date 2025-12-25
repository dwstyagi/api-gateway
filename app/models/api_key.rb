class ApiKey < ApplicationRecord
  # Available scopes for API keys
  AVAILABLE_SCOPES = [
    'read:all',
    'write:all',
    'read:orders',
    'write:orders',
    'read:users',
    'write:users',
    'read:products',
    'write:products',
    'admin:*',
    '*:*'
  ].freeze

  # Associations
  belongs_to :user

  # Validations
  validates :key_hash, presence: true, uniqueness: true
  validates :name, presence: true
  validates :prefix, presence: true
  validates :scopes, presence: true
  validates :status, presence: true,
                     inclusion: { in: %w[active revoked deprecated] }

  # Callbacks
  before_create :generate_key_hash
  after_create :cache_in_redis

  # Scopes
  scope :active, -> { where(status: 'active') }
  scope :revoked, -> { where(status: 'revoked') }
  scope :for_user, ->(user_id) { where(user_id: user_id) }

  # Virtual attribute to hold the plaintext key (only available at creation)
  attr_accessor :plaintext_key

  # Generate a new API key with prefix
  # Returns hash with success status, api_key object, and plaintext key (shown only once)
  def self.generate_for_user(user, name:, scopes:, environment: :live)
    prefix = environment.to_s == 'test' ? "pk_test_" : "pk_live_"
    random_part = SecureRandom.hex(16) # 32 characters
    plaintext = "#{prefix}#{random_part}"

    api_key = new(
      user: user,
      name: name,
      prefix: prefix,
      key_hash: hash_key(plaintext),  # Set hash directly
      scopes: scopes,
      status: 'active'
    )

    if api_key.save
      {
        success: true,
        api_key: api_key,
        raw_key: plaintext  # Return the plaintext key - this is the ONLY time it's available
      }
    else
      {
        success: false,
        error: api_key.errors.full_messages.join(', '),
        api_key: api_key
      }
    end
  end

  # Authenticate with plaintext API key
  def self.authenticate(plaintext_key)
    key_hash = hash_key(plaintext_key)
    api_key = find_by(key_hash: key_hash, status: 'active')

    # Update last_used_at timestamp
    api_key&.touch(:last_used_at)

    api_key
  end

  # Hash the API key using SHA256
  def self.hash_key(plaintext_key)
    Digest::SHA256.hexdigest(plaintext_key)
  end

  # Check if key has specific scope
  def has_scope?(required_scope)
    # Check for wildcard permission
    return true if scopes.include?('*:*')

    # Parse required scope (e.g., "orders:read")
    resource, action = required_scope.split(':')

    # Check for exact match or wildcard variations
    scopes.include?(required_scope) ||
      scopes.include?("#{resource}:*") ||
      scopes.include?("*:#{action}")
  end

  # Revoke this API key
  def revoke!
    update!(status: 'revoked')
    remove_from_redis
  end

  # Mark key as deprecated (grace period before full revocation)
  def deprecate!
    update!(status: 'deprecated')
  end

  # Check if key is expired
  def expired?
    expires_at.present? && expires_at < Time.current
  end

  # Check if key is usable
  def usable?
    status == 'active' && !expired?
  end

  private

  def generate_key_hash
    return if plaintext_key.blank?

    self.key_hash = self.class.hash_key(plaintext_key)
  end

  def cache_in_redis
    # Cache API key data in Redis for fast lookups
    # Key format: apikey:{hash}
    $redis.hset("apikey:#{key_hash}", {
      user_id: user_id,
      name: name,
      scopes: scopes.to_json,
      status: status,
      created_at: created_at.iso8601
    })
  end

  def remove_from_redis
    $redis.del("apikey:#{key_hash}")
  end
end
