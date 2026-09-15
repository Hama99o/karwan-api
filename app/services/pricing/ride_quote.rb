module Pricing
  # Prices a ride. Same shape as a delivery quote, different formula.
  #
  # base + per-kilometre + per-minute, floored at a minimum. The per-minute term
  # is what stops a short journey through heavy Kabul traffic being priced as if
  # it were quick — distance alone underpays the driver who sits in it.
  #
  # Model A on a ride is the simpler half: the courier collects the fare, keeps
  # it, and owes commission from their prepaid wallet. Nothing is advanced to
  # anybody, which is why `Trip#wallet_requirement` is zero and a courier too
  # short for a delivery can still take a ride.
  class RideQuote
    Error = Class.new(StandardError)

    def initialize(pickup_latitude:, pickup_longitude:, dropoff_latitude:, dropoff_longitude:)
      @pickup_latitude = pickup_latitude
      @pickup_longitude = pickup_longitude
      @dropoff_latitude = dropoff_latitude
      @dropoff_longitude = dropoff_longitude
    end

    def call
      raise Error, "both pins are required to price a ride" if route.nil?

      Quote.new(
        distance_km: distance_km,
        duration_minutes: duration_minutes,
        route: route,
        currency: Monetary::DEFAULT_CURRENCY,
        amounts: {
          fare: fare,
          commission: commission,
          courier_earnings: (fare - commission).round(2)
        }
      )
    end

    private

    def route
      return @route if defined?(@route)

      @route = Routing::DistanceResolver.new(
        from_lat: @pickup_latitude, from_lng: @pickup_longitude,
        to_lat: @dropoff_latitude, to_lng: @dropoff_longitude
      ).call
    end

    def distance_km
      route&.distance_km
    end

    # From `eta_average_speed_kmh`, not OSRM's free-flow estimate.
    def duration_minutes
      route&.duration_minutes
    end

    def fare
      @fare ||= begin
        computed = Setting.fetch("trip_base_fare") +
                   (Setting.fetch("trip_fare_per_km") * BigDecimal(distance_km.to_s)) +
                   (Setting.fetch("trip_fare_per_minute") * (duration_minutes || 0))

        [ computed, Setting.fetch("trip_minimum_fare") ].max.round(2)
      end
    end

    # Rounded DOWN to the minor unit in the platform's favour by never rounding
    # the courier's share up past the fare: `courier_earnings` is derived by
    # subtraction, so the two always reconstitute the fare exactly and
    # `Trip#fare_splits_correctly` cannot fail on a rounding artefact.
    def commission
      @commission ||= (fare * Setting.fetch("trip_commission_rate")).round(2)
    end
  end
end
