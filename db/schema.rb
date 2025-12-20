# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_12_20_162711) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "api_definitions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", limit: 255, null: false
    t.string "route_pattern", limit: 255, null: false
    t.string "backend_url", limit: 500, null: false
    t.string "allowed_methods", default: ["GET", "POST", "PUT", "DELETE"], array: true
    t.boolean "enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["enabled"], name: "index_api_definitions_on_enabled"
    t.index ["name"], name: "index_api_definitions_on_name", unique: true
  end

  create_table "api_keys", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.string "key_hash", limit: 64, null: false
    t.string "name", limit: 255, null: false
    t.string "prefix", limit: 20, null: false
    t.text "scopes", default: [], null: false, array: true
    t.string "status", limit: 20, default: "active", null: false
    t.datetime "expires_at"
    t.datetime "last_used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key_hash"], name: "index_api_keys_on_key_hash", unique: true
    t.index ["status"], name: "index_api_keys_on_status"
    t.index ["user_id", "status"], name: "index_api_keys_on_user_id_and_status"
    t.index ["user_id"], name: "index_api_keys_on_user_id"
  end

  create_table "audit_logs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "timestamp", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "event_type", limit: 100, null: false
    t.uuid "actor_user_id"
    t.string "actor_ip", limit: 45
    t.string "resource_type", limit: 50
    t.string "resource_id", limit: 255
    t.jsonb "changes"
    t.jsonb "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_user_id"], name: "index_audit_logs_on_actor_user_id"
    t.index ["changes"], name: "index_audit_logs_on_changes", using: :gin
    t.index ["event_type"], name: "index_audit_logs_on_event_type"
    t.index ["metadata"], name: "index_audit_logs_on_metadata", using: :gin
    t.index ["resource_type", "resource_id"], name: "index_audit_logs_on_resource"
    t.index ["timestamp"], name: "index_audit_logs_on_timestamp"
  end

  create_table "ip_rules", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "ip_address", limit: 45, null: false
    t.string "rule_type", limit: 20, null: false
    t.string "reason", limit: 500
    t.boolean "auto_blocked", default: false, null: false
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ip_address", "rule_type"], name: "index_ip_rules_on_ip_and_type"
    t.index ["ip_address"], name: "index_ip_rules_on_ip_address"
    t.index ["rule_type"], name: "index_ip_rules_on_rule_type"
  end

  create_table "rate_limit_policies", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "api_definition_id", null: false
    t.string "tier", limit: 50
    t.string "strategy", limit: 50, null: false
    t.integer "capacity", null: false
    t.integer "refill_rate"
    t.integer "window_seconds"
    t.string "redis_failure_mode", limit: 10, default: "open", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["api_definition_id", "tier"], name: "index_policies_on_api_and_tier", unique: true
    t.index ["api_definition_id"], name: "index_rate_limit_policies_on_api_definition_id"
    t.index ["tier"], name: "index_rate_limit_policies_on_tier"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "email", limit: 255, null: false
    t.string "password_digest", null: false
    t.string "role", limit: 50, default: "user", null: false
    t.string "tier", limit: 50, default: "free", null: false
    t.integer "token_version", default: 1, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["role"], name: "index_users_on_role"
    t.index ["tier"], name: "index_users_on_tier"
  end

  add_foreign_key "api_keys", "users"
  add_foreign_key "rate_limit_policies", "api_definitions"
end
