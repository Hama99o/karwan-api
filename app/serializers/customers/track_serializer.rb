module Customers
  # WHERE THE ORDER IS, for the customer's map. Three points and nothing else.
  #
  # ── Why this is its own endpoint and not fields on the order ─────────────
  # `OrderPolicy#track?` was written with this exact shape in mind and then
  # never consulted by anything — the precise failure `docs/NOTES.md` records
  # from edu-safi: "the correct scope existed, was correct, and was never
  # called". It refuses a TERMINAL order, which fields on the order serializer
  # could not: a customer reading last week's delivered order would otherwise
  # watch that courier for the rest of their shift.
  #
  # It is also the only payload the app polls while a courier is moving, so it
  # stays small on purpose — AFGHAN_UX.md §5, data costs the user real money.
  #
  # ── A stale fix is not a location ────────────────────────────────────────
  # `CourierProfile::STALE_AFTER` is five minutes and DISPATCH REFUSES a fix
  # older than that. The customer's map holds the same line: past that age the
  # position is withheld rather than drawn, because a pin that has not moved in
  # twenty minutes reads as "he is standing still", which is a different and
  # much worse lie than "we do not know where he is".
  class TrackSerializer < ApplicationSerializer
    identifier :id

    fields :code, :status

    field :is_live do |order|
      !order.terminal?
    end

    # The merchant's pin, so the app can draw the leg the courier is on. Not a
    # privacy question: the same coordinates are already public on
    # `/public/merchants/:id` — it is a shop.
    field :pickup do |order|
      next nil if order.merchant&.latitude.nil? || order.merchant&.longitude.nil?

      { latitude: order.merchant.latitude, longitude: order.merchant.longitude,
        name: order.merchant.name, landmark_note: order.merchant.landmark_note }
    end

    # Their own pin, echoed back. The app has it locally when it placed the
    # order, but not after a reinstall or on a second device.
    field :dropoff do |order|
      { latitude: order.delivery_latitude, longitude: order.delivery_longitude,
        landmark_note: order.delivery_landmark_note }
    end

    field :courier do |order|
      next nil if order.courier.nil?

      profile = order.courier.courier_profile
      coordinates = profile&.coordinates
      # Both conditions, not either: a fresh timestamp with no coordinates is a
      # courier who reported once and then not at all, and coordinates with a
      # stale timestamp are where they used to be.
      fresh = (profile&.location_fresh? && coordinates.present?) || false

      {
        # First name only, as everywhere else the customer sees a courier.
        name: order.courier.display_name.to_s.split.first,
        phone: order.courier.phone,
        location: fresh ? { latitude: coordinates[0], longitude: coordinates[1] } : nil,
        location_fresh: fresh,
        located_at: profile&.location_updated_at
      }
    end
  end
end
