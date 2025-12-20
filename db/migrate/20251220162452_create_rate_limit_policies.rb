class CreateRateLimitPolicies < ActiveRecord::Migration[8.0]
  def change
    create_table :rate_limit_policies, id: :uuid do |t|
      # Foreign key to api_definitions table
      t.references :api_definition, type: :uuid, null: false, foreign_key: true

      # User tier this policy applies to (e.g., 'free', 'pro', 'enterprise')
      # NULL means default policy for all users
      t.string :tier, limit: 50

      # Rate limiting strategy: 'token_bucket', 'fixed_window', 'sliding_window', 'leaky_bucket', 'concurrency'
      t.string :strategy, null: false, limit: 50

      # Maximum capacity (tokens, requests, or concurrent connections depending on strategy)
      t.integer :capacity, null: false

      # Refill rate (for token_bucket and leaky_bucket strategies)
      # Number of tokens/requests added per second
      t.integer :refill_rate

      # Window size in seconds (for fixed_window and sliding_window strategies)
      t.integer :window_seconds

      # Behavior when Redis is unavailable: 'open' (allow) or 'closed' (deny)
      t.string :redis_failure_mode, null: false, default: 'open', limit: 10

      t.timestamps
    end

    # Composite unique index - one policy per (api_definition + tier) combination
    add_index :rate_limit_policies, [:api_definition_id, :tier], unique: true, name: 'index_policies_on_api_and_tier'

    # Note: Index on api_definition_id is automatically created by t.references

    # Index on tier for querying policies by user tier
    add_index :rate_limit_policies, :tier
  end
end
