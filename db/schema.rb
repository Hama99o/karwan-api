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

ActiveRecord::Schema[8.1].define(version: 2026_09_15_121100) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"

  create_table "addresses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.boolean "is_default", default: false, null: false
    t.string "label"
    t.text "landmark_note"
    t.decimal "latitude", precision: 10, scale: 6, null: false
    t.decimal "longitude", precision: 10, scale: 6, null: false
    t.string "phone"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["deleted_at"], name: "index_addresses_on_kept", where: "(deleted_at IS NULL)"
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

  create_table "courier_profiles", force: :cascade do |t|
    t.boolean "accepts_food_orders", default: true, null: false
    t.boolean "accepts_trips", default: false, null: false
    t.datetime "created_at", null: false
    t.string "father_name"
    t.string "full_name"
    t.string "guarantor_name"
    t.string "guarantor_phone"
    t.string "guarantor_relation"
    t.boolean "is_available", default: false, null: false
    t.decimal "last_latitude", precision: 10, scale: 6
    t.decimal "last_longitude", precision: 10, scale: 6
    t.datetime "location_updated_at"
    t.string "national_id_number"
    t.string "plate_number"
    t.text "rejection_reason"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.integer "vehicle_type", default: 0, null: false
    t.integer "verification_status", default: 0, null: false
    t.datetime "verified_at"
    t.bigint "verified_by_id"
    t.text "work_area"
    t.index ["accepts_food_orders", "is_available"], name: "index_courier_profiles_on_food_availability"
    t.index ["accepts_trips", "is_available"], name: "index_courier_profiles_on_trip_availability"
    t.index ["is_available"], name: "index_courier_profiles_on_is_available"
    t.index ["national_id_number"], name: "index_courier_profiles_on_national_id_number"
    t.index ["user_id"], name: "index_courier_profiles_on_user_id", unique: true
    t.index ["verification_status"], name: "index_courier_profiles_on_verification_status"
  end

  create_table "courier_wallets", force: :cascade do |t|
    t.decimal "balance", precision: 12, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.decimal "credit_line", precision: 12, scale: 2, default: "0.0", null: false
    t.string "currency", default: "AFN", null: false
    t.string "top_up_code", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["top_up_code"], name: "index_courier_wallets_on_top_up_code", unique: true
    t.index ["user_id"], name: "index_courier_wallets_on_user_id", unique: true
  end

  create_table "cuisines", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "is_active", default: true, null: false
    t.string "name_en", null: false
    t.string "name_fa", null: false
    t.string "name_ps", null: false
    t.integer "position", default: 0, null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["is_active", "position"], name: "index_cuisines_on_is_active_and_position"
    t.index ["name_en"], name: "index_cuisines_on_name_en_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["slug"], name: "index_cuisines_on_slug", unique: true
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
    t.datetime "deleted_at"
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.bigint "restaurant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_menu_categories_on_kept", where: "(deleted_at IS NULL)"
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
    t.datetime "deleted_at"
    t.text "description"
    t.boolean "is_available", default: true, null: false
    t.bigint "menu_category_id", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.integer "prep_time_minutes"
    t.decimal "price", precision: 12, scale: 2, null: false
    t.bigint "restaurant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_menu_items_on_kept", where: "(deleted_at IS NULL)"
    t.index ["menu_category_id", "position"], name: "index_menu_items_on_menu_category_id_and_position"
    t.index ["menu_category_id"], name: "index_menu_items_on_menu_category_id"
    t.index ["name"], name: "index_menu_items_on_name_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["restaurant_id", "is_available"], name: "index_menu_items_on_restaurant_id_and_is_available"
    t.index ["restaurant_id"], name: "index_menu_items_on_restaurant_id"
  end

  create_table "offers", force: :cascade do |t|
    t.bigint "courier_id", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "offerable_id", null: false
    t.string "offerable_type", null: false
    t.datetime "offered_at", null: false
    t.datetime "responded_at"
    t.integer "sequence", default: 1, null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["courier_id", "status"], name: "index_offers_on_courier_id_and_status"
    t.index ["courier_id"], name: "index_offers_on_courier_id"
    t.index ["expires_at"], name: "index_offers_on_expires_at"
    t.index ["offerable_type", "offerable_id", "sequence"], name: "index_offers_on_offerable_and_sequence", unique: true
    t.index ["offerable_type", "offerable_id"], name: "index_offers_on_offerable"
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

  create_table "orders", force: :cascade do |t|
    t.datetime "accepted_at"
    t.integer "cancellation_reason"
    t.datetime "cancelled_at"
    t.integer "cancelled_by_role"
    t.string "code", null: false
    t.decimal "commission", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "courier_fee", precision: 12, scale: 2, default: "0.0", null: false
    t.bigint "courier_id"
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
    t.integer "payment_status", default: 0, null: false
    t.datetime "picked_up_at"
    t.datetime "placed_at"
    t.datetime "preparing_at"
    t.datetime "ready_at"
    t.datetime "rejected_at"
    t.integer "rejection_reason"
    t.bigint "restaurant_id", null: false
    t.datetime "restaurant_paid_at"
    t.decimal "restaurant_payout", precision: 12, scale: 2, default: "0.0", null: false
    t.datetime "settled_at"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_orders_on_code", unique: true
    t.index ["courier_id", "payment_status"], name: "index_orders_on_courier_id_and_payment_status"
    t.index ["courier_id"], name: "index_orders_on_courier_id"
    t.index ["created_at"], name: "index_orders_on_created_at"
    t.index ["customer_id"], name: "index_orders_on_customer_id"
    t.index ["payment_status"], name: "index_orders_on_payment_status"
    t.index ["restaurant_id", "status"], name: "index_orders_on_restaurant_id_and_status"
    t.index ["restaurant_id"], name: "index_orders_on_restaurant_id"
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

  create_table "restaurant_cuisines", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "cuisine_id", null: false
    t.bigint "restaurant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["cuisine_id"], name: "index_restaurant_cuisines_on_cuisine_id"
    t.index ["restaurant_id", "cuisine_id"], name: "index_restaurant_cuisines_on_restaurant_id_and_cuisine_id", unique: true
    t.index ["restaurant_id"], name: "index_restaurant_cuisines_on_restaurant_id"
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
    t.string "contact_person_name"
    t.string "contact_person_phone"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.text "description"
    t.boolean "is_open", default: false, null: false
    t.text "landmark_note"
    t.decimal "latitude", precision: 10, scale: 6
    t.string "license_number"
    t.decimal "longitude", precision: 10, scale: 6
    t.string "name", null: false
    t.bigint "owner_id"
    t.string "owner_name"
    t.string "owner_national_id_number"
    t.string "owner_phone"
    t.string "phone", null: false
    t.integer "prep_time_minutes", default: 20, null: false
    t.text "rejection_reason"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.datetime "verified_at"
    t.bigint "verified_by_id"
    t.index ["deleted_at"], name: "index_restaurants_on_kept", where: "(deleted_at IS NULL)"
    t.index ["is_open"], name: "index_restaurants_on_is_open"
    t.index ["name"], name: "index_restaurants_on_name"
    t.index ["name"], name: "index_restaurants_on_name_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["owner_id"], name: "index_restaurants_on_owner_id"
    t.index ["owner_phone"], name: "index_restaurants_on_owner_phone"
    t.index ["status"], name: "index_restaurants_on_status"
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
    t.bigint "courier_id", null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "AFN", null: false
    t.decimal "expected_amount", precision: 12, scale: 2, null: false
    t.text "note"
    t.datetime "period_end"
    t.datetime "period_start"
    t.datetime "settled_at", null: false
    t.datetime "updated_at", null: false
    t.index ["counted_by_id"], name: "index_settlements_on_counted_by_id"
    t.index ["courier_id", "settled_at"], name: "index_settlements_on_courier_id_and_settled_at"
    t.index ["courier_id"], name: "index_settlements_on_courier_id"
  end

  create_table "status_transitions", force: :cascade do |t|
    t.bigint "actor_id"
    t.integer "actor_role"
    t.datetime "created_at", null: false
    t.string "from_status"
    t.text "reason"
    t.bigint "subject_id", null: false
    t.string "subject_type", null: false
    t.string "to_status", null: false
    t.index ["actor_id"], name: "index_status_transitions_on_actor_id"
    t.index ["subject_type", "subject_id", "created_at"], name: "index_status_transitions_on_subject_and_time"
    t.index ["subject_type", "subject_id"], name: "index_status_transitions_on_subject"
  end

  create_table "trips", force: :cascade do |t|
    t.datetime "accepted_at"
    t.datetime "arrived_at"
    t.integer "cancellation_reason"
    t.datetime "cancelled_at"
    t.integer "cancelled_by_role"
    t.string "code", null: false
    t.decimal "commission", precision: 12, scale: 2, default: "0.0", null: false
    t.datetime "completed_at"
    t.decimal "courier_earnings", precision: 12, scale: 2, default: "0.0", null: false
    t.bigint "courier_id"
    t.datetime "created_at", null: false
    t.string "currency", default: "AFN", null: false
    t.decimal "distance_km", precision: 8, scale: 3
    t.text "dropoff_landmark_note"
    t.decimal "dropoff_latitude", precision: 10, scale: 6, null: false
    t.decimal "dropoff_longitude", precision: 10, scale: 6, null: false
    t.integer "duration_minutes"
    t.datetime "failed_at"
    t.integer "failure_reason"
    t.decimal "fare", precision: 12, scale: 2, default: "0.0", null: false
    t.text "notes"
    t.bigint "passenger_id", null: false
    t.string "passenger_phone", null: false
    t.integer "payment_method", default: 0, null: false
    t.integer "payment_status", default: 0, null: false
    t.text "pickup_landmark_note"
    t.decimal "pickup_latitude", precision: 10, scale: 6, null: false
    t.decimal "pickup_longitude", precision: 10, scale: 6, null: false
    t.datetime "requested_at"
    t.datetime "settled_at"
    t.datetime "started_at"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_trips_on_code", unique: true
    t.index ["courier_id", "payment_status"], name: "index_trips_on_courier_id_and_payment_status"
    t.index ["courier_id"], name: "index_trips_on_courier_id"
    t.index ["created_at"], name: "index_trips_on_created_at"
    t.index ["passenger_id"], name: "index_trips_on_passenger_id"
    t.index ["payment_status"], name: "index_trips_on_payment_status"
    t.index ["status", "created_at"], name: "index_trips_on_status_and_created_at"
    t.index ["status"], name: "index_trips_on_status"
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
    t.datetime "deleted_at"
    t.string "locale", default: "fa", null: false
    t.string "name"
    t.string "phone", null: false
    t.datetime "phone_verified_at"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_users_on_kept", where: "(deleted_at IS NULL)"
    t.index ["phone"], name: "index_users_on_phone", unique: true
    t.index ["status"], name: "index_users_on_status"
  end

  create_table "wallet_entries", force: :cascade do |t|
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.decimal "balance_after", precision: 12, scale: 2, null: false
    t.bigint "courier_wallet_id", null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "AFN", null: false
    t.integer "kind", null: false
    t.text "note"
    t.bigint "recorded_by_id"
    t.bigint "source_id"
    t.string "source_type"
    t.index ["courier_wallet_id", "created_at"], name: "index_wallet_entries_on_courier_wallet_id_and_created_at"
    t.index ["courier_wallet_id"], name: "index_wallet_entries_on_courier_wallet_id"
    t.index ["kind"], name: "index_wallet_entries_on_kind"
    t.index ["recorded_by_id"], name: "index_wallet_entries_on_recorded_by_id"
    t.index ["source_type", "source_id"], name: "index_wallet_entries_on_source"
  end

  add_foreign_key "addresses", "users"
  add_foreign_key "audit_logs", "users", column: "actor_id"
  add_foreign_key "courier_profiles", "users"
  add_foreign_key "courier_profiles", "users", column: "verified_by_id"
  add_foreign_key "courier_wallets", "users"
  add_foreign_key "device_tokens", "users"
  add_foreign_key "menu_categories", "restaurants"
  add_foreign_key "menu_item_option_values", "menu_item_options"
  add_foreign_key "menu_item_options", "menu_items"
  add_foreign_key "menu_items", "menu_categories"
  add_foreign_key "menu_items", "restaurants"
  add_foreign_key "offers", "users", column: "courier_id"
  add_foreign_key "order_item_options", "order_items"
  add_foreign_key "order_items", "menu_items"
  add_foreign_key "order_items", "orders"
  add_foreign_key "orders", "restaurants"
  add_foreign_key "orders", "users", column: "courier_id"
  add_foreign_key "orders", "users", column: "customer_id"
  add_foreign_key "restaurant_cuisines", "cuisines"
  add_foreign_key "restaurant_cuisines", "restaurants"
  add_foreign_key "restaurant_opening_hours", "restaurants"
  add_foreign_key "restaurants", "users", column: "owner_id"
  add_foreign_key "restaurants", "users", column: "verified_by_id"
  add_foreign_key "settings", "users", column: "updated_by_id"
  add_foreign_key "settlements", "users", column: "counted_by_id"
  add_foreign_key "settlements", "users", column: "courier_id"
  add_foreign_key "status_transitions", "users", column: "actor_id"
  add_foreign_key "trips", "users", column: "courier_id"
  add_foreign_key "trips", "users", column: "passenger_id"
  add_foreign_key "user_roles", "users"
  add_foreign_key "user_sessions", "users"
  add_foreign_key "wallet_entries", "courier_wallets"
  add_foreign_key "wallet_entries", "users", column: "recorded_by_id"
end
