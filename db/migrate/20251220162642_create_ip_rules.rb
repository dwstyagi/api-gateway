class CreateIpRules < ActiveRecord::Migration[8.0]
  def change
    create_table :ip_rules, id: :uuid do |t|
      # IP address to block or allow (supports both IPv4 and IPv6)
      t.string :ip_address, null: false, limit: 45

      # Rule type: 'block' or 'allow'
      t.string :rule_type, null: false, limit: 20

      # Human-readable reason for the rule (e.g., "Brute force detected", "VPN abuse")
      t.string :reason, limit: 500

      # Flag indicating if this was auto-blocked by the system
      t.boolean :auto_blocked, null: false, default: false

      # Optional expiration timestamp for temporary blocks
      t.datetime :expires_at

      t.timestamps
    end

    # Index on ip_address for fast lookup during request processing
    add_index :ip_rules, :ip_address

    # Index on rule_type for filtering blocks vs allows
    add_index :ip_rules, :rule_type

    # Composite index for checking if IP is blocked (most common query)
    add_index :ip_rules, [:ip_address, :rule_type], name: 'index_ip_rules_on_ip_and_type'
  end
end
