require "administrate/base_dashboard"

# The live order board — the screen someone watches all evening.
class OrderDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    code: Field::String,
    status: Field::Select.with_options(collection: ->(_f) { Order.statuses.keys }),
    payment_status: Field::Select.with_options(collection: ->(_f) { Order.payment_statuses.keys }),
    customer: Field::BelongsTo.with_options(class_name: "User"),
    merchant: Field::BelongsTo,
    courier: Field::BelongsTo.with_options(class_name: "User"),
    items_total: Field::Number.with_options(decimals: 2),
    delivery_fee: Field::Number.with_options(decimals: 2),
    commission: Field::Number.with_options(decimals: 2),
    courier_fee: Field::Number.with_options(decimals: 2),
    merchant_payout: Field::Number.with_options(decimals: 2),
    customer_total: Field::Number.with_options(decimals: 2),
    currency: Field::String,
    customer_phone: Field::String,
    delivery_landmark_note: Field::Text,
    notes: Field::Text,
    distance_km: Field::Number.with_options(decimals: 3),
    distance_source: Field::String,
    order_items: Field::HasMany,
    transitions: Field::HasMany.with_options(class_name: "StatusTransition"),
    offers: Field::HasMany,
    placed_at: Field::DateTime,
    accepted_at: Field::DateTime,
    ready_at: Field::DateTime,
    picked_up_at: Field::DateTime,
    delivered_at: Field::DateTime,
    created_at: Field::DateTime
  }.freeze

  # Ordered for the question the operator is actually asking: what state is it
  # in, how long has it been there, and who is on it. Age is the column the
  # board is watched for, so it sits next to the state rather than at the end.
  COLLECTION_ATTRIBUTES = %i[code status payment_status merchant courier customer_total].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    code status payment_status customer merchant courier
    items_total delivery_fee commission courier_fee merchant_payout customer_total currency
    customer_phone delivery_landmark_note notes distance_km distance_source
    order_items transitions offers
    placed_at accepted_at ready_at picked_up_at delivered_at created_at
  ].freeze

  # An operator does not hand-edit an order — every change goes through a named
  # intervention that writes an audit row. Leaving the generic form open would
  # let someone rewrite a total with no record of why.
  FORM_ATTRIBUTES = [].freeze

  COLLECTION_FILTERS = {
    live: ->(resources) { resources.live },
    overdue: ->(resources) { resources.live.overdue },
    unsettled: ->(resources) { resources.unsettled },
    unassigned: ->(resources) { resources.live.where(courier_id: nil) }
  }.freeze

  def display_resource(order)
    "#{order.code} — #{order.status}"
  end
end
