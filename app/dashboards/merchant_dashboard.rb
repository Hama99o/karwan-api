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
    # THE PHOTOS THE CUSTOMER HOME IS BUILT FROM. Merchants are not self-serve
    # in v0 — admin onboards them — so this form is the ONLY way a storefront
    # photo can ever reach the app, and AFGHAN_UX.md §1 puts photos first: "a
    # photo sells and explains where a description cannot."
    logo: AttachmentField,
    storefront_photo: AttachmentField,
    license_photo: AttachmentField,
    verified_at: Field::DateTime,
    verified_by_admin_user: Field::BelongsTo.with_options(class_name: "AdminUser"),
    rejection_reason: Field::Text,
    deleted_at: Field::DateTime,
    catalog_categories: Field::HasMany,
    catalog_items: Field::HasMany,
    created_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[name merchant_kind status owner_phone is_open phone commission_rate].freeze
  SHOW_PAGE_ATTRIBUTES = %i[
    name merchant_kind phone status is_open prep_time_minutes commission_rate
    latitude longitude landmark_note owner owner_name owner_phone
    owner_national_id_number license_number contact_person_name contact_person_phone
    verified_at verified_by_admin_user rejection_reason deleted_at
    logo storefront_photo license_photo catalog_categories catalog_items created_at
  ].freeze
  # Admin onboards merchants, so unlike orders the form IS the workflow — but
  # commission_rate is here deliberately: a deal struck with one restaurant is
  # typed in, not deployed.
  FORM_ATTRIBUTES = %i[
    name merchant_kind phone status prep_time_minutes commission_rate
    latitude longitude landmark_note owner owner_name owner_phone
    owner_national_id_number license_number contact_person_name contact_person_phone
    logo storefront_photo license_photo
  ].freeze

  COLLECTION_FILTERS = {
    open_now: ->(resources) { resources.where(is_open: true) },
    # THE CALL LIST. Shops that asked through the app and that nobody has
    # spoken to — the only queue in this console with a person waiting by a
    # phone at the other end of it.
    leads: ->(resources) { resources.leads.order(created_at: :desc) },
    pending: ->(resources) { resources.status_pending },
    discarded: ->(resources) { resources.discarded }
  }.freeze

  def display_resource(merchant)
    merchant.name
  end
end
