class ApiDefinition < ApplicationRecord
  # Associations
  has_many :rate_limit_policies, dependent: :destroy

  # Validations
  validates :name, presence: true,
                   uniqueness: true,
                   format: { with: /\A[a-z0-9\-_]+\z/, message: "only allows lowercase letters, numbers, hyphens, and underscores" }

  validates :route_pattern, presence: true

  validates :backend_url, presence: true,
                          format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), message: "must be a valid HTTP/HTTPS URL" }

  validates :allowed_methods, presence: true

  validate :validate_allowed_methods

  # Scopes
  scope :enabled, -> { where(enabled: true) }
  scope :disabled, -> { where(enabled: false) }

  # Check if a request path matches this API's route pattern
  def matches_route?(path)
    pattern_regex = route_pattern.gsub('*', '.*')
    path.match?(/\A#{pattern_regex}\z/)
  end

  # Check if HTTP method is allowed
  def method_allowed?(http_method)
    allowed_methods.include?(http_method.to_s.upcase)
  end

  # Get rate limit policy for a specific tier
  def policy_for_tier(tier)
    rate_limit_policies.find_by(tier: tier) || rate_limit_policies.find_by(tier: nil)
  end

  # Enable/disable API
  def enable!
    update!(enabled: true)
  end

  def disable!
    update!(enabled: false)
  end

  private

  def validate_allowed_methods
    return if allowed_methods.blank?

    valid_methods = %w[GET POST PUT PATCH DELETE HEAD OPTIONS]
    invalid_methods = allowed_methods - valid_methods

    if invalid_methods.any?
      errors.add(:allowed_methods, "contains invalid HTTP methods: #{invalid_methods.join(', ')}")
    end
  end
end
