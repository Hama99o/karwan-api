require "administrate/base_dashboard"

# One thing on one menu. `is_available` is the sold-out toggle, which is the
# control a merchant reaches for most often on a busy evening.
#
# Not routed: the merchant owns their menu. This page exists so support can SEE
# what a customer ordered from, and so the currency is visible next to the
# price — never sum across currencies.
class CatalogItemDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    merchant: Field::BelongsTo,
    catalog_category: Field::BelongsTo,
    name: Field::String,
    description: Field::Text,
    price: Field::Number.with_options(decimals: 2),
    currency: Field::String,
    is_available: Field::Boolean,
    prep_time_minutes: Field::Number,
    position: Field::Number,
    deleted_at: Field::DateTime,
    created_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[name price currency is_available].freeze
  SHOW_PAGE_ATTRIBUTES = %i[
    merchant catalog_category name description price currency is_available
    prep_time_minutes position deleted_at created_at
  ].freeze
  FORM_ATTRIBUTES = [].freeze

  def display_resource(item)
    item.name
  end
end
