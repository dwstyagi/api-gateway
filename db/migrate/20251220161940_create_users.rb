class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    # Using UUID for security (prevents user enumeration attacks)
    create_table :users, id: :uuid do |t|
      # Email used as unique login identifier
      t.string :email, null: false, limit: 255

      # BCrypt hash of password - never store plain text passwords
      t.string :password_digest, null: false

      # Role-based access control: 'user' or 'admin'
      t.string :role, null: false, default: 'user', limit: 50

      # User tier determines rate limit policies: 'free', 'pro', 'enterprise'
      t.string :tier, null: false, default: 'free', limit: 50

      # Token version for JWT revocation strategy
      # Incremented when user changes password or logs out of all devices
      # Gateway compares JWT version with this value to validate tokens
      t.integer :token_version, null: false, default: 1

      t.timestamps
    end

    # Unique index on email for fast login lookups and uniqueness enforcement
    add_index :users, :email, unique: true

    # Index on role for admin queries and filtering
    add_index :users, :role

    # Index on tier for analytics and batch operations
    add_index :users, :tier
  end
end
