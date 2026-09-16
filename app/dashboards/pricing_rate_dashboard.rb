require "administrate/base_dashboard"

# THE PRICES, EDITABLE WITH NO DEPLOY — which is the whole point of correction
# 13. Hamma9900 tunes these against the market; he said 80% accuracy is enough
# to start and that he would calibrate.
#
# Read the two demand types as DIFFERENT THINGS, because they are:
#
#   ride / customer     — what a passenger pays for that class. They pick it,
#                         so the price may depend on it and still be honest.
#   delivery / courier  — what a courier earns on that vehicle. The customer
#                         never sees it; the delivery fee they pay is a
#                         `Setting`, because it has no vehicle dimension.
#
# A courier rate ABOVE the customer fee is allowed on purpose — subsidising a
# zarang to win a segment is a decision he is entitled to make. It is not
# refused, so it has to be visible: the Money panel on the console root says
# the delivery margin is "so far", not booked.
class PricingRateDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    job_kind: Field::Select.with_options(collection: ->(_f) { PricingRate::JOB_KINDS }),
    audience: Field::Select.with_options(collection: ->(_f) { PricingRate.audiences.keys }),
    vehicle_type: Field::Select.with_options(
      collection: ->(_f) { PricingRate.vehicle_types.keys }, include_blank: true
    ),
    base: Field::Number.with_options(decimals: 2),
    per_km: Field::Number.with_options(decimals: 2),
    per_minute: Field::Number.with_options(decimals: 2),
    minimum: Field::Number.with_options(decimals: 2),
    currency: Field::String,
    is_selectable: Field::Boolean,
    position: Field::Number,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[job_kind audience vehicle_type base per_km per_minute minimum].freeze
  SHOW_PAGE_ATTRIBUTES = %i[
    job_kind audience vehicle_type base per_km per_minute minimum currency
    is_selectable position updated_at
  ].freeze
  # The numbers, and whether a passenger may choose the class. Not `job_kind`,
  # `audience` or `vehicle_type`: changing those on an existing row silently
  # repoints a tariff at a different vehicle, and the unique index would then
  # refuse the save with an error nobody can read. Add a row instead.
  FORM_ATTRIBUTES = %i[base per_km per_minute minimum is_selectable position].freeze

  COLLECTION_FILTERS = {
    rides: ->(resources) { resources.for_job(Trip::JOB_KIND) },
    deliveries: ->(resources) { resources.for_job(Order::JOB_KIND) },
    passenger_choices: ->(resources) { resources.selectable }
  }.freeze

  def display_resource(rate)
    "#{rate.job_kind} · #{rate.audience} · #{rate.vehicle_type || 'any vehicle'}"
  end
end
