require "administrate/base_dashboard"

# One chosen option value, snapshotted: the option's name, the value's name and
# the price delta as text and numbers. Not routed; rendered inside an order line.
class OrderItemOptionDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    order_item: Field::BelongsTo,
    option_name: Field::String,
    value_name: Field::String,
    price_delta: Field::Number.with_options(decimals: 2),
    currency: Field::String,
    created_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[option_name value_name price_delta].freeze
  SHOW_PAGE_ATTRIBUTES = %i[order_item option_name value_name price_delta currency created_at].freeze
  FORM_ATTRIBUTES = [].freeze

  def display_resource(option)
    "#{option.option_name}: #{option.value_name}"
  end
end
