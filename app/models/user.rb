class User < ApplicationRecord
  # BCrypt integration for password hashing
  # Adds password and password_confirmation attributes
  # Validates password presence and confirmation
  has_secure_password

  # Associations
  has_many :api_keys, dependent: :destroy
  has_many :audit_logs, foreign_key: :actor_user_id, dependent: :nullify

  # Validations
  validates :email, presence: true,
                    uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }

  validates :role, presence: true,
                   inclusion: { in: %w[user admin] }

  validates :tier, presence: true,
                   inclusion: { in: %w[free pro enterprise] }

  validates :token_version, presence: true,
                            numericality: { only_integer: true, greater_than: 0 }

  # Callbacks
  before_save :downcase_email

  # Scopes
  scope :admins, -> { where(role: 'admin') }
  scope :regular_users, -> { where(role: 'user') }
  scope :by_tier, ->(tier) { where(tier: tier) }

  # Token versioning methods for JWT revocation
  def invalidate_all_tokens!
    increment!(:token_version)
  end

  def token_valid?(version)
    version == token_version
  end

  # Check if user is admin
  def admin?
    role == 'admin'
  end

  # Get user's rate limit tier
  def rate_limit_tier
    tier
  end

  private

  def downcase_email
    self.email = email.downcase if email.present?
  end
end
