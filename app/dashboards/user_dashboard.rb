require "administrate/base_dashboard"

class UserDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    phone: Field::String,
    name: Field::String,
    locale: Field::Select.with_options(collection: ->(_f) { User::LOCALES }),
    last_active_role: Field::Select.with_options(collection: ->(_f) { User.last_active_roles.keys }),
    status: Field::Select.with_options(collection: ->(_f) { User.statuses.keys }),
    phone_verified_at: Field::DateTime,
    user_roles: Field::HasMany,
    addresses: Field::HasMany,
    courier_profile: Field::HasOne,
    courier_wallet: Field::HasOne,
    # Counts and dates, never a credential — see User#live_session_count.
    # `searchable: false` on both, and the reason is not style: Administrate
    # builds its search as a SQL LIKE over every string attribute, and these two
    # are COMPUTED METHODS rather than columns. Without it, searching users dies
    # on `column users.registered_devices_summary does not exist` — which is how
    # the full suite caught it after the admin folder alone had passed.
    live_session_count: Field::Number.with_options(searchable: false),
    registered_devices_summary: Field::String.with_options(searchable: false),
    deleted_at: Field::DateTime,
    created_at: Field::DateTime
  }.freeze

  # `deleted_at` in the list for the same reason as on MerchantDashboard: a
  # discarded courier is already listed here and looked live.
  COLLECTION_ATTRIBUTES = %i[phone name last_active_role status deleted_at created_at].freeze
  SHOW_PAGE_ATTRIBUTES = %i[
    phone name locale last_active_role status phone_verified_at
    live_session_count registered_devices_summary user_roles addresses
    courier_profile courier_wallet deleted_at created_at
  ].freeze
  FORM_ATTRIBUTES = %i[name locale status].freeze

  COLLECTION_FILTERS = {
    couriers: ->(resources) { resources.with_role(:courier) },
    merchant_owners: ->(resources) { resources.with_role(:merchant_owner) },
    suspended: ->(resources) { resources.where(status: :suspended) }
  }.freeze

  def display_resource(user)
    user.display_name
  end
end
