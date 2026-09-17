module Pricing
  # What every quote returns: the distance it was priced from, the time it
  # implies, and every amount, already rounded to the minor unit.
  #
  # A struct rather than a Hash so a typo is a NoMethodError at the call site
  # instead of a silent nil that becomes a zero fee.
  # `route` carries how the distance was measured, the drawn line, and how far
  # each pin was from a road. It rides along INSIDE the quote rather than
  # behind a second endpoint: the fare is frozen server-side from this exact
  # route, and the mobile app draws this exact geometry. Two calls could
  # disagree.
  # `lines` is the priced basket — WHY the total is what it is. It defaults to
  # empty because a RIDE has no lines, and it is here rather than behind a
  # second endpoint for the same reason `route` is: the customer must see the
  # figures the order will be frozen with, and two calls could disagree.
  # `dispatch_warning` is the honest half of the vehicle question: nil when
  # there is nothing to say, otherwise a machine-readable key the app renders
  # in Pashto. It exists because "no suitable vehicle is online right now" must
  # NOT refuse the order — that is a five-minute problem and refusing it turns
  # a delivery we could have had into a customer who leaves — but the customer
  # deserves to know before they commit, so they can decide to wait or to order
  # something else. A permanent inability to carry the thing is a refusal
  # instead, raised by `Orders::PlaceService`.
  # `shortage_multiplier` and its `_requested` twin are NOT in `amounts`, on
  # purpose: `amounts` is money and is checked as money — the parts must sum to
  # the whole — and a multiplier is neither a part nor a total. They ride
  # beside it, like `distance_km`, as an input the fee was computed FROM.
  #
  # THEY ARE ALSO NOT IN `to_attributes`, and that is not an oversight.
  # `to_attributes` is consumed by BOTH `Orders::PlaceService` and the ride
  # path building a `Trip`, and `trips` has no such column — a shortage applies
  # to deliveries today and to rides only when somebody builds it. So the
  # caller that knows which table it is filling merges these two, and adding
  # them here would break a Trip with an `UnknownAttributeError`. Measured, not
  # reasoned: it did.
  Quote = Data.define(:distance_km, :duration_minutes, :currency, :amounts, :route, :lines,
                      :dispatch_warning, :shortage_multiplier, :shortage_multiplier_requested) do
    def initialize(lines: [], dispatch_warning: nil,
                   shortage_multiplier: Pricing::ShortageMultiplier::NONE,
                   shortage_multiplier_requested: Pricing::ShortageMultiplier::NONE, **rest)
      super(lines: lines, dispatch_warning: dispatch_warning,
            shortage_multiplier: shortage_multiplier,
            shortage_multiplier_requested: shortage_multiplier_requested, **rest)
    end

    def to_attributes
      amounts.merge(
        currency: currency,
        distance_km: distance_km,
        duration_minutes: duration_minutes,
        distance_source: route&.source,
        route_geometry: route&.geometry,
        origin_snap_metres: route&.origin_snap_metres,
        destination_snap_metres: route&.destination_snap_metres
      )
    end
  end
end
