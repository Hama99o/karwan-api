require "administrate/base_dashboard"

# A line on an order, as it was AT ORDER TIME. One-way door #1: the name, the
# price and the options are a snapshot, not a join, so this page shows what was
# actually bought even after the merchant renames or reprices the item.
#
# Not routed — there is no `/admin/order_items`. It exists because the order
# page renders its lines, and Administrate resolves an associated dashboard by
# class name.
class OrderItemDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    order: Field::BelongsTo,
    catalog_item: Field::BelongsTo,
    name: Field::String,
    quantity: Field::Number,
    unit_price: Field::Number.with_options(decimals: 2),
    options_total: Field::Number.with_options(decimals: 2),
    line_total: Field::Number.with_options(decimals: 2),
    currency: Field::String,
    notes: Field::Text,
    selected_options: Field::HasMany,
    # RENDERED ON THE ORDER PAGE, not behind a route. `selected_options` above
    # is a HasMany whose dashboard nothing can open — see OrderItem#options_summary.
    options_summary: Field::String,
    created_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[name quantity options_summary unit_price options_total line_total].freeze
  SHOW_PAGE_ATTRIBUTES = %i[
    order name quantity options_summary unit_price options_total line_total currency notes
    selected_options created_at
  ].freeze
  # Nothing. A snapshot that can be edited is not a snapshot.
  FORM_ATTRIBUTES = [].freeze

  def display_resource(item)
    "#{item.quantity} × #{item.name}"
  end
end
