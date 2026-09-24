require "administrate/base_dashboard"

# ONE OFFER, TO ONE COURIER, WITH A DEADLINE. This is the page that answers
# "why did this order sit for four minutes" — the offer sequence, who each one
# went to, and whether they declined or let it time out. That question is the
# reason `Offer` is a table rather than a field.
#
# Not routed: dispatch is driven by `Dispatch::OfferService` and the redispatch
# intervention, both of which log. Hand-editing an offer row would create a
# dispatch decision nobody made.
class OfferDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    offerable: Field::Polymorphic,
    courier: Field::BelongsTo.with_options(class_name: "User"),
    sequence: Field::Number,
    status: Field::String,
    offered_at: Field::DateTime,
    expires_at: Field::DateTime,
    responded_at: Field::DateTime,
    # What dispatch chose him by: the time of his fix, and the straight-line
    # distance to the pickup it gave. Fix age = offered_at - courier_located_at.
    courier_located_at: Field::DateTime,
    distance_km: Field::Number.with_options(decimals: 3)
  }.freeze

  COLLECTION_ATTRIBUTES = %i[sequence courier status offered_at responded_at].freeze
  SHOW_PAGE_ATTRIBUTES = %i[
    offerable courier sequence status offered_at expires_at responded_at
    courier_located_at distance_km
  ].freeze
  FORM_ATTRIBUTES = [].freeze

  def display_resource(offer)
    "##{offer.sequence} to #{offer.courier&.display_name || 'nobody'} — #{offer.status}"
  end
end
