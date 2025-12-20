class CreateAuditLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :audit_logs, id: :uuid do |t|
      # When the event occurred
      t.datetime :timestamp, null: false, default: -> { 'CURRENT_TIMESTAMP' }

      # Type of event (e.g., 'user.login', 'api_key.created', 'admin.policy_updated')
      t.string :event_type, null: false, limit: 100

      # User who performed the action (nullable for system events)
      t.uuid :actor_user_id

      # IP address of the actor
      t.string :actor_ip, limit: 45

      # Type of resource affected (e.g., 'api_key', 'user', 'policy')
      t.string :resource_type, limit: 50

      # ID of the affected resource
      t.string :resource_id, limit: 255

      # JSON object containing change details (before/after values)
      t.jsonb :changes

      # Additional metadata as JSON (e.g., user_agent, request_id, etc.)
      t.jsonb :metadata

      # Index timestamp for created_at is automatic
      # We create a custom timestamp column for more control
      t.timestamps
    end

    # Index on timestamp for time-based queries (most common: recent events)
    add_index :audit_logs, :timestamp

    # Index on event_type for filtering by event
    add_index :audit_logs, :event_type

    # Index on actor_user_id for finding all actions by a user
    add_index :audit_logs, :actor_user_id

    # Composite index for resource lookups (e.g., "show me all changes to this API key")
    add_index :audit_logs, [:resource_type, :resource_id], name: 'index_audit_logs_on_resource'

    # GIN index on JSONB columns for fast JSON queries
    add_index :audit_logs, :changes, using: :gin
    add_index :audit_logs, :metadata, using: :gin
  end
end
