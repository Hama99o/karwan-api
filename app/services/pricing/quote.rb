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
  Quote = Data.define(:distance_km, :duration_minutes, :currency, :amounts, :route, :lines) do
    def initialize(lines: [], **rest)
      super(lines: lines, **rest)
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
