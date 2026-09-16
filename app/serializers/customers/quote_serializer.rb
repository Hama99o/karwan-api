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

    # WHAT TO BRING. This returned the total unchanged, which made it useless —
    # so the mobile app computed its own advice, which put a money rule on the
    # device and let the cart and the status screen disagree. `Monetary` owns it
    # now: nil when nothing needs saying, otherwise the next 500.
    field :suggested_notes do |quote|
      Monetary.change_advice(quote.amounts[:customer_total])
    end

    # WHY the total is what it is, line by line, every figure computed by the
    # server. `CartResolver` produced these all along and `QuoteService`
    # discarded them, which left the app summing catalog prices itself —
    # exactly the failure CLAUDE.md forbids and edu-safi shipped three times.
    #
    # The option NAMES ride along too, so the cart can show "Large · +100"
    # without re-deriving which values were chosen.
    field :lines do |quote|
      quote.lines.map do |line|
        {
          catalog_item_id: line[:item].id,
          name: line[:item].name,
          quantity: line[:quantity],
          unit_price: line[:item].price,
          options_total: line[:options_total],
          line_total: line[:line_total],
          currency: line[:item].currency,
          notes: line[:notes],
          options: line[:values].map do |value|
            { id: value.id, name: value.name, price_delta: value.price_delta }
          end
        }
      end
    end

    # WHETHER TO WAIT OR TO ORDER SOMETHING ELSE. A key, never prose: the
    # server cannot write Pashto, so the app renders its own copy. Nil for
    # every food order, which is every order today.
    field :dispatch_warning do |quote|
      quote.dispatch_warning
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
