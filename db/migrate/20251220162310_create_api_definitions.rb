class CreateApiDefinitions < ActiveRecord::Migration[8.0]
  def change
    create_table :api_definitions, id: :uuid do |t|
      # Unique name identifier for the API (e.g., "orders-api", "users-api")
      t.string :name, null: false, limit: 255

      # URL pattern to match incoming requests (e.g., "/api/orders/*")
      # Gateway uses this to determine which backend to proxy to
      t.string :route_pattern, null: false, limit: 255

      # Backend service URL where requests should be proxied
      # (e.g., "http://orders-service:3000", "https://api.backend.com")
      t.string :backend_url, null: false, limit: 500

      # Allowed HTTP methods as array (e.g., ["GET", "POST", "PUT", "DELETE"])
      # Requests with other methods will be rejected
      t.string :allowed_methods, array: true, default: ['GET', 'POST', 'PUT', 'DELETE']

      # Flag to enable/disable this API without deleting the definition
      t.boolean :enabled, null: false, default: true

      t.timestamps
    end

    # Unique index on name - each API must have unique identifier
    add_index :api_definitions, :name, unique: true

    # Index on enabled flag for filtering active APIs
    add_index :api_definitions, :enabled
  end
end
