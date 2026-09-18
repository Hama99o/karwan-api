require "administrate/base_dashboard"

# "Large, +100". One choice inside an option.
#
# `price_delta` may be NEGATIVE — "no rice, −20" is a real menu line — so the
# console must not treat it as a price. `currency` is absent from the form for
# the same reason it is absent from the item's: it defaults to AFN, and an
# operator typing a currency is the front door to a mixed-currency total.
class CatalogItemOptionValueDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    catalog_item_option: Field::BelongsTo,
    name: Field::String,
    price_delta: Field::Number.with_options(decimals: 2),
    currency: Field::String,
    is_available: Field::Boolean,
    position: Field::Number,
    created_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[catalog_item_option name price_delta is_available].freeze
  SHOW_PAGE_ATTRIBUTES = %i[
    catalog_item_option name price_delta currency is_available position created_at
  ].freeze
  FORM_ATTRIBUTES = %i[catalog_item_option name price_delta is_available position].freeze

  def display_resource(value)
    delta = value.price_delta.to_d
    delta.zero? ? value.name : "#{value.name} (#{delta.positive? ? '+' : ''}#{delta.to_i})"
  end
end
