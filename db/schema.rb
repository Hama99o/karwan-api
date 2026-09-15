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

ActiveRecord::Schema[8.1].define(version: 2026_09_15_120700) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "addresses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "is_default", default: false, null: false
    t.string "label"
    t.text "landmark_note"
    t.decimal "latitude", precision: 10, scale: 6, null: false
    t.decimal "longitude", precision: 10, scale: 6, null: false
    t.string "phone"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "is_default"], name: "index_addresses_on_user_id_and_is_default"
    t.index ["user_id"], name: "index_addresses_on_user_id"
  end

  create_table "audit_logs", force: :cascade do |t|
    t.string "action", null: false
    t.bigint "actor_id"
    t.integer "actor_role"
    t.jsonb "after"
    t.jsonb "before"
    t.datetime "created_at", null: false
    t.jsonb "details"
    t.string "ip"
    t.bigint "target_id"
    t.string "target_type"
    t.index ["action"], name: "index_audit_logs_on_action"
    t.index ["actor_id"], name: "index_audit_logs_on_actor_id"
    t.index ["created_at"], name: "index_audit_logs_on_created_at"
    t.index ["target_type", "target_id"], name: "index_audit_logs_on_target"
  end

  create_table "device_tokens", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "last_seen_at"
    t.integer "platform", default: 0, null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["token"], name: "index_device_tokens_on_token", unique: true
    t.index ["user_id", "active"], name: "index_device_tokens_on_user_id_and_active"
    t.index ["user_id"], name: "index_device_tokens_on_user_id"
  end

  create_table "menu_categories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.bigint "restaurant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["restaurant_id", "position"], name: "index_menu_categories_on_restaurant_id_and_position"
    t.index ["restaurant_id"], name: "index_menu_categories_on_restaurant_id"
  end

  create_table "menu_item_option_values", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency", default: "AFN", null: false
    t.boolean "is_available", default: true, null: false
    t.bigint "menu_item_option_id", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.decimal "price_delta", precision: 12, scale: 2, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.index ["menu_item_option_id", "position"], name: "idx_on_menu_item_option_id_position_6e3df27dc8"
    t.index ["menu_item_option_id"], name: "index_menu_item_option_values_on_menu_item_option_id"
  end

  create_table "menu_item_options", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "max_selections"
    t.bigint "menu_item_id", null: false
    t.integer "min_selections", default: 0, null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.boolean "required", default: false, null: false
    t.integer "selection_type", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["menu_item_id", "position"], name: "index_menu_item_options_on_menu_item_id_and_position"
    t.index ["menu_item_id"], name: "index_menu_item_options_on_menu_item_id"
  end

  create_table "menu_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency", default: "AFN", null: false
    t.text "description"
    t.boolean "is_available", default: true, null: false
    t.bigint "menu_category_id", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.integer "prep_time_minutes"
    t.decimal "price", precision: 12, scale: 2, null: false
    t.bigint "restaurant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["menu_category_id", "position"], name: "index_menu_items_on_menu_category_id_and_position"
    t.index ["menu_category_id"], name: "index_menu_items_on_menu_category_id"
    t.index ["restaurant_id", "is_available"], name: "index_menu_items_on_restaurant_id_and_is_available"
    t.index ["restaurant_id"], name: "index_menu_items_on_restaurant_id"
  end

  create_table "order_item_options", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency", default: "AFN", null: false
    t.string "option_name", null: false
    t.bigint "order_item_id", null: false
    t.decimal "price_delta", precision: 12, scale: 2, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.string "value_name", null: false
    t.index ["order_item_id"], name: "index_order_item_options_on_order_item_id"
  end

  create_table "order_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency", default: "AFN", null: false
    t.decimal "line_total", precision: 12, scale: 2, null: false
    t.bigint "menu_item_id"
    t.string "name", null: false
    t.text "notes"
    t.decimal "options_total", precision: 12, scale: 2, default: "0.0", null: false
    t.bigint "order_id", null: false
    t.integer "quantity", default: 1, null: false
    t.decimal "unit_price", precision: 12, scale: 2, null: false
    t.datetime "updated_at", null: false
    t.index ["menu_item_id"], name: "index_order_items_on_menu_item_id"
    t.index ["order_id"], name: "index_order_items_on_order_id"
  end

  create_table "order_offers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.datetime "offered_at", null: false
    t.bigint "order_id", null: false
    t.datetime "responded_at"
    t.bigint "rider_id", null: false
    t.integer "sequence", default: 1, null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_order_offers_on_expires_at"
    t.index ["order_id", "sequence"], name: "index_order_offers_on_order_id_and_sequence", unique: true
    t.index ["order_id"], name: "index_order_offers_on_order_id"
    t.index ["rider_id", "status"], name: "index_order_offers_on_rider_id_and_status"
    t.index ["rider_id"], name: "index_order_offers_on_rider_id"
  end

  create_table "order_status_transitions", force: :cascade do |t|
    t.bigint "actor_id"
    t.integer "actor_role"
    t.datetime "created_at", null: false
    t.integer "from_status"
    t.bigint "order_id", null: false
    t.text "reason"
    t.integer "to_status", null: false
    t.index ["actor_id"], name: "index_order_status_transitions_on_actor_id"
    t.index ["order_id", "created_at"], name: "index_order_status_transitions_on_order_id_and_created_at"
    t.index ["order_id"], name: "index_order_status_transitions_on_order_id"
  end

  create_table "orders", force: :cascade do |t|
    t.datetime "accepted_at"
    t.integer "cancellation_reason"
    t.datetime "cancelled_at"
    t.integer "cancelled_by_role"
    t.integer "cash_status", default: 0, null: false
    t.string "code", null: false
    t.decimal "commission", precision: 12, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "AFN", null: false
    t.bigint "customer_id", null: false
    t.string "customer_phone", null: false
    t.decimal "customer_total", precision: 12, scale: 2, default: "0.0", null: false
    t.datetime "delivered_at"
    t.decimal "delivery_fee", precision: 12, scale: 2, default: "0.0", null: false
    t.text "delivery_landmark_note"
    t.decimal "delivery_latitude", precision: 10, scale: 6, null: false
    t.decimal "delivery_longitude", precision: 10, scale: 6, null: false
    t.datetime "failed_at"
    t.integer "failure_reason"
    t.decimal "food_total", precision: 12, scale: 2, default: "0.0", null: false
    t.text "notes"
    t.integer "payment_method", default: 0, null: false
    t.datetime "picked_up_at"
    t.datetime "placed_at"
    t.datetime "preparing_at"
    t.datetime "ready_at"
    t.datetime "rejected_at"
    t.integer "rejection_reason"
    t.bigint "restaurant_id", null: false
    t.datetime "restaurant_paid_at"
    t.decimal "restaurant_payout", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "rider_fee", precision: 12, scale: 2, default: "0.0", null: false
    t.bigint "rider_id"
    t.datetime "settled_at"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["cash_status"], name: "index_orders_on_cash_status"
    t.index ["code"], name: "index_orders_on_code", unique: true
    t.index ["created_at"], name: "index_orders_on_created_at"
    t.index ["customer_id"], name: "index_orders_on_customer_id"
    t.index ["restaurant_id", "status"], name: "index_orders_on_restaurant_id_and_status"
    t.index ["restaurant_id"], name: "index_orders_on_restaurant_id"
    t.index ["rider_id", "cash_status"], name: "index_orders_on_rider_id_and_cash_status"
    t.index ["rider_id"], name: "index_orders_on_rider_id"
    t.index ["status", "created_at"], name: "index_orders_on_status_and_created_at"
    t.index ["status"], name: "index_orders_on_status"
  end

  create_table "otp_verifications", force: :cascade do |t|
    t.integer "attempts_count", default: 0, null: false
    t.string "code_digest", null: false
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "phone", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_otp_verifications_on_expires_at"
    t.index ["phone", "created_at"], name: "index_otp_verifications_on_phone_and_created_at"
  end

  create_table "restaurant_opening_hours", force: :cascade do |t|
    t.time "closes_at", null: false
    t.datetime "created_at", null: false
    t.integer "day_of_week", null: false
    t.time "opens_at", null: false
    t.bigint "restaurant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["restaurant_id", "day_of_week"], name: "idx_on_restaurant_id_day_of_week_50cf7ea8db"
    t.index ["restaurant_id"], name: "index_restaurant_opening_hours_on_restaurant_id"
  end

  create_table "restaurants", force: :cascade do |t|
    t.decimal "commission_rate", precision: 5, scale: 4, default: "0.125", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "is_open", default: false, null: false
    t.text "landmark_note"
    t.decimal "latitude", precision: 10, scale: 6
    t.decimal "longitude", precision: 10, scale: 6
    t.string "name", null: false
    t.bigint "owner_id"
    t.string "phone", null: false
    t.integer "prep_time_minutes", default: 20, null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["is_open"], name: "index_restaurants_on_is_open"
    t.index ["name"], name: "index_restaurants_on_name"
    t.index ["owner_id"], name: "index_restaurants_on_owner_id"
    t.index ["status"], name: "index_restaurants_on_status"
  end

  create_table "rider_profiles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "is_available", default: false, null: false
    t.decimal "last_latitude", precision: 10, scale: 6
    t.decimal "last_longitude", precision: 10, scale: 6
    t.datetime "location_updated_at"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["is_available"], name: "index_rider_profiles_on_is_available"
    t.index ["user_id"], name: "index_rider_profiles_on_user_id", unique: true
  end

  create_table "rider_wallets", force: :cascade do |t|
    t.decimal "balance", precision: 12, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.decimal "credit_line", precision: 12, scale: 2, default: "0.0", null: false
    t.string "currency", default: "AFN", null: false
    t.string "top_up_code", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["top_up_code"], name: "index_rider_wallets_on_top_up_code", unique: true
    t.index ["user_id"], name: "index_rider_wallets_on_user_id", unique: true
  end

  create_table "settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency"
    t.text "description"
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.bigint "updated_by_id"
    t.string "value"
    t.integer "value_type", default: 0, null: false
    t.index ["key"], name: "index_settings_on_key", unique: true
    t.index ["updated_by_id"], name: "index_settings_on_updated_by_id"
  end

  create_table "settlements", force: :cascade do |t|
    t.decimal "counted_amount", precision: 12, scale: 2, null: false
    t.bigint "counted_by_id"
    t.string "counted_by_name", null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "AFN", null: false
    t.decimal "expected_amount", precision: 12, scale: 2, null: false
    t.text "note"
    t.datetime "period_end"
    t.datetime "period_start"
    t.bigint "rider_id", null: false
    t.datetime "settled_at", null: false
    t.datetime "updated_at", null: false
    t.index ["counted_by_id"], name: "index_settlements_on_counted_by_id"
    t.index ["rider_id", "settled_at"], name: "index_settlements_on_rider_id_and_settled_at"
    t.index ["rider_id"], name: "index_settlements_on_rider_id"
  end

  create_table "user_roles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "role", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "role"], name: "index_user_roles_on_user_id_and_role", unique: true
    t.index ["user_id"], name: "index_user_roles_on_user_id"
  end

  create_table "user_sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "device_name"
    t.datetime "expires_at"
    t.datetime "last_used_at"
    t.string "platform"
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["token_digest"], name: "index_user_sessions_on_token_digest", unique: true
    t.index ["user_id"], name: "index_user_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.integer "active_role", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "locale", default: "fa", null: false
    t.string "name"
    t.string "phone", null: false
    t.datetime "phone_verified_at"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["phone"], name: "index_users_on_phone", unique: true
    t.index ["status"], name: "index_users_on_status"
  end

  create_table "wallet_entries", force: :cascade do |t|
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.decimal "balance_after", precision: 12, scale: 2, null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "AFN", null: false
    t.integer "kind", null: false
    t.text "note"
    t.bigint "order_id"
    t.bigint "recorded_by_id"
    t.bigint "rider_wallet_id", null: false
    t.index ["kind"], name: "index_wallet_entries_on_kind"
    t.index ["order_id"], name: "index_wallet_entries_on_order_id"
    t.index ["recorded_by_id"], name: "index_wallet_entries_on_recorded_by_id"
    t.index ["rider_wallet_id", "created_at"], name: "index_wallet_entries_on_rider_wallet_id_and_created_at"
    t.index ["rider_wallet_id"], name: "index_wallet_entries_on_rider_wallet_id"
  end

  add_foreign_key "addresses", "users"
  add_foreign_key "audit_logs", "users", column: "actor_id"
  add_foreign_key "device_tokens", "users"
  add_foreign_key "menu_categories", "restaurants"
  add_foreign_key "menu_item_option_values", "menu_item_options"
  add_foreign_key "menu_item_options", "menu_items"
  add_foreign_key "menu_items", "menu_categories"
  add_foreign_key "menu_items", "restaurants"
  add_foreign_key "order_item_options", "order_items"
  add_foreign_key "order_items", "menu_items"
  add_foreign_key "order_items", "orders"
  add_foreign_key "order_offers", "orders"
  add_foreign_key "order_offers", "users", column: "rider_id"
  add_foreign_key "order_status_transitions", "orders"
  add_foreign_key "order_status_transitions", "users", column: "actor_id"
  add_foreign_key "orders", "restaurants"
  add_foreign_key "orders", "users", column: "customer_id"
  add_foreign_key "orders", "users", column: "rider_id"
  add_foreign_key "restaurant_opening_hours", "restaurants"
  add_foreign_key "restaurants", "users", column: "owner_id"
  add_foreign_key "rider_profiles", "users"
  add_foreign_key "rider_wallets", "users"
  add_foreign_key "settings", "users", column: "updated_by_id"
  add_foreign_key "settlements", "users", column: "counted_by_id"
  add_foreign_key "settlements", "users", column: "rider_id"
  add_foreign_key "user_roles", "users"
  add_foreign_key "user_sessions", "users"
  add_foreign_key "wallet_entries", "orders"
  add_foreign_key "wallet_entries", "rider_wallets"
  add_foreign_key "wallet_entries", "users", column: "recorded_by_id"
end
