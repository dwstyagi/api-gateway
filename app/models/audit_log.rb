class AuditLog < ApplicationRecord
  # Associations
  belongs_to :actor, class_name: 'User', foreign_key: :actor_user_id, optional: true

  # Validations
  validates :timestamp, presence: true
  validates :event_type, presence: true

  # Scopes
  scope :recent, -> { order(timestamp: :desc) }
  scope :by_event_type, ->(type) { where(event_type: type) }
  scope :by_actor, ->(user_id) { where(actor_user_id: user_id) }
  scope :by_resource, ->(type, id) { where(resource_type: type, resource_id: id) }
  scope :in_time_range, ->(start_time, end_time) { where(timestamp: start_time..end_time) }

  # Event type constants for consistency
  module EventTypes
    # Authentication events
    USER_LOGIN = 'user.login'
    USER_LOGOUT = 'user.logout'
    USER_LOGIN_FAILED = 'user.login_failed'

    # API Key events
    API_KEY_CREATED = 'api_key.created'
    API_KEY_REVOKED = 'api_key.revoked'
    API_KEY_ROTATED = 'api_key.rotated'
    API_KEY_SCOPES_UPDATED = 'api_key.scopes_updated'

    # Admin events
    API_DEFINITION_CREATED = 'api_definition.created'
    API_DEFINITION_UPDATED = 'api_definition.updated'
    API_DEFINITION_DELETED = 'api_definition.deleted'
    POLICY_CREATED = 'policy.created'
    POLICY_UPDATED = 'policy.updated'
    POLICY_DELETED = 'policy.deleted'

    # Security events
    IP_BLOCKED = 'security.ip_blocked'
    IP_UNBLOCKED = 'security.ip_unblocked'
    AUTO_BLOCK_TRIGGERED = 'security.auto_block_triggered'
    BRUTE_FORCE_DETECTED = 'security.brute_force_detected'
  end

  # Log an event with automatic timestamp
  def self.log_event(event_type:, actor_user: nil, actor_ip: nil, resource_type: nil, resource_id: nil, changes: nil, metadata: nil)
    create!(
      timestamp: Time.current,
      event_type: event_type,
      actor_user_id: actor_user&.id,
      actor_ip: actor_ip,
      resource_type: resource_type,
      resource_id: resource_id,
      changes: changes,
      metadata: metadata
    )
  end

  # Helper method to query JSONB fields
  def self.with_metadata_key(key, value)
    where("metadata @> ?", { key => value }.to_json)
  end

  def self.with_change_to(field)
    where("changes ? :field", field: field)
  end

  # Get human-readable event description
  def description
    case event_type
    when EventTypes::USER_LOGIN
      "User logged in"
    when EventTypes::API_KEY_CREATED
      "API key created: #{resource_id}"
    when EventTypes::IP_BLOCKED
      "IP address blocked: #{changes&.dig('ip_address')}"
    else
      event_type.humanize
    end
  end

  # Check if this is a security event
  def security_event?
    event_type.start_with?('security.')
  end

  # Check if this is an admin action
  def admin_action?
    event_type.start_with?('api_definition.', 'policy.')
  end
end
