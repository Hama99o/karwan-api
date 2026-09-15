require "administrate/base_dashboard"

class TripDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    code: Field::String,
    status: Field::Select.with_options(collection: ->(_f) { Trip.statuses.keys }),
    payment_status: Field::Select.with_options(collection: ->(_f) { Trip.payment_statuses.keys }),
    passenger: Field::BelongsTo.with_options(class_name: "User"),
    courier: Field::BelongsTo.with_options(class_name: "User"),
    fare: Field::Number.with_options(decimals: 2),
    commission: Field::Number.with_options(decimals: 2),
    courier_earnings: Field::Number.with_options(decimals: 2),
    currency: Field::String,
    passenger_phone: Field::String,
    pickup_landmark_note: Field::Text,
    dropoff_landmark_note: Field::Text,
    distance_km: Field::Number.with_options(decimals: 3),
    distance_source: Field::String,
    duration_minutes: Field::Number,
    transitions: Field::HasMany.with_options(class_name: "StatusTransition"),
    requested_at: Field::DateTime,
    completed_at: Field::DateTime,
    created_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[code status payment_status passenger courier fare].freeze
  SHOW_PAGE_ATTRIBUTES = %i[
    code status payment_status passenger courier fare commission courier_earnings currency
    passenger_phone pickup_landmark_note dropoff_landmark_note
    distance_km distance_source duration_minutes transitions requested_at completed_at created_at
  ].freeze
  FORM_ATTRIBUTES = [].freeze

  COLLECTION_FILTERS = {
    live: ->(resources) { resources.live },
    overdue: ->(resources) { resources.live.overdue },
    unsettled: ->(resources) { resources.unsettled }
  }.freeze

  def display_resource(trip)
    "#{trip.code} — #{trip.status}"
  end
end
