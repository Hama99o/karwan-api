require "administrate/base_dashboard"

class MerchantDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    name: Field::String,
    merchant_kind: Field::BelongsTo,
    phone: Field::String,
    status: Field::Select.with_options(collection: ->(_f) { Merchant.statuses.keys }),
    is_open: Field::Boolean,
    prep_time_minutes: Field::Number,
    commission_rate: Field::Number.with_options(decimals: 4),
    latitude: Field::Number.with_options(decimals: 6),
    longitude: Field::Number.with_options(decimals: 6),
    landmark_note: Field::Text,
    owner: Field::BelongsTo.with_options(class_name: "User"),
    owner_name: Field::String,
    owner_phone: Field::String,
    owner_national_id_number: Field::String,
    license_number: Field::String,
    contact_person_name: Field::String,
    contact_person_phone: Field::String,
    verified_at: Field::DateTime,
    rejection_reason: Field::Text,
    deleted_at: Field::DateTime,
    catalog_categories: Field::HasMany,
    catalog_items: Field::HasMany,
    created_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[name merchant_kind status is_open phone commission_rate].freeze
  SHOW_PAGE_ATTRIBUTES = %i[
    name merchant_kind phone status is_open prep_time_minutes commission_rate
    latitude longitude landmark_note owner owner_name owner_phone
    owner_national_id_number license_number contact_person_name contact_person_phone
    verified_at rejection_reason deleted_at catalog_categories catalog_items created_at
  ].freeze
  # Admin onboards merchants, so unlike orders the form IS the workflow — but
  # commission_rate is here deliberately: a deal struck with one restaurant is
  # typed in, not deployed.
  FORM_ATTRIBUTES = %i[
    name merchant_kind phone status prep_time_minutes commission_rate
    latitude longitude landmark_note owner owner_name owner_phone
    owner_national_id_number license_number contact_person_name contact_person_phone
  ].freeze

  COLLECTION_FILTERS = {
    open_now: ->(resources) { resources.where(is_open: true) },
    pending: ->(resources) { resources.status_pending },
    discarded: ->(resources) { resources.discarded }
  }.freeze

  def display_resource(merchant)
    merchant.name
  end
end
