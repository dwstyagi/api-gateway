class CreateApiKeys < ActiveRecord::Migration[8.0]
  def change
    create_table :api_keys, id: :uuid do |t|
      # Foreign key to users table
      t.references :user, type: :uuid, null: false, foreign_key: true

      # SHA256 hash of the API key - original key is never stored
      # Only the hash is stored for security (like password hashing)
      t.string :key_hash, null: false, limit: 64

      # User-friendly name for the key (e.g., "Production Backend", "Mobile App")
      t.string :name, null: false, limit: 255

      # Key prefix for identification (e.g., "pk_live_", "pk_test_")
      # Helps users identify key type and environment
      t.string :prefix, null: false, limit: 20

      # Permissions/scopes as array (e.g., ["orders:read", "orders:write"])
      # Users can define granular permissions for each key
      t.text :scopes, array: true, null: false, default: []

      # Key status: 'active', 'revoked', 'deprecated'
      t.string :status, null: false, default: 'active', limit: 20

      # Optional expiration timestamp
      t.datetime :expires_at

      # Track when key was last used for security auditing
      t.datetime :last_used_at

      t.timestamps
    end

    # Index on key_hash for fast lookup during authentication
    # This is the primary query: "SELECT * FROM api_keys WHERE key_hash = ?"
    add_index :api_keys, :key_hash, unique: true

    # Note: Index on user_id is automatically created by t.references

    # Index on status for filtering active/revoked keys
    add_index :api_keys, :status

    # Composite index for user's active keys (common query pattern)
    add_index :api_keys, [:user_id, :status]
  end
end
