module Customers
  # A price BEFORE the order exists.
  #
  # Correction 4: money is shown before it is owed, at every step, for every
  # role. A customer must see the total before they commit, and it must be the
  # same number they are asked for at the door — so it comes from the same
  # `Pricing::DeliveryQuote` the order itself will use, not from a second
  # formula that can drift.
  class QuoteSerializer < ApplicationSerializer
    fields :distance_km, :duration_minutes, :currency

    field :items_total do |quote|
      quote.amounts[:items_total]
    end

    field :delivery_fee do |quote|
      quote.amounts[:delivery_fee]
    end

    field :amount_to_pay_in_cash do |quote|
      quote.amounts[:customer_total]
    end

    # So the app can warn "you will need change" rather than the courier
    # discovering it on a doorstep. Couriers carry a float, but a 5,000 note
    # for a 500 order is still a problem.
    field :suggested_notes do |quote|
      quote.amounts[:customer_total]
    end

    # How the distance was measured. Exposed rather than hidden because the
    # fare has to be explainable — and because during the switch from
    # straight-line to routed, "which did this one use" is the first question.
    field :distance_source do |quote|
      quote.route&.source
    end

    # The drawn line, GeoJSON, consumed directly by MapLibre as a ShapeSource.
    # Nil on the straight-line fallback, which the app renders as a plain line
    # between the pins.
    field :route_geometry do |quote|
      quote.route&.geometry
    end

    # True when a pin is not on the mapped road network — a walled compound, a
    # perimeter, an unmapped lane. The app should lean harder on the landmark
    # voice note when this is set, rather than trusting the map.
    field :pin_far_from_road do |quote|
      quote.route&.pin_far_from_road? || false
    end
  end
end
