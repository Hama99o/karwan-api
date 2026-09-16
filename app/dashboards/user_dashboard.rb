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
    deleted_at: Field::DateTime,
    created_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[phone name last_active_role status created_at].freeze
  SHOW_PAGE_ATTRIBUTES = %i[
    phone name locale last_active_role status phone_verified_at user_roles addresses
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
