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

    # `vehicle_type` is WHAT THE PASSENGER CHOSE, and it is why this fare can
    # depend on the vehicle while staying upfront and frozen: the class is
    # picked before the price is calculated. A motorbike ride is much cheaper
    # than a car and the passenger is the right person to decide between cheap
    # and comfortable — hiding that choice would mean either quoting a car and
    # dispatching a bike, or a price that moves after they agreed.
    #
    # Nil falls back to the any-vehicle rate, so a caller that has not asked
    # the question yet still gets a price rather than an exception.
    def initialize(pickup_latitude:, pickup_longitude:, dropoff_latitude:, dropoff_longitude:,
                   vehicle_type: nil, service_tier: :normal)
      @pickup_latitude = pickup_latitude
      @pickup_longitude = pickup_longitude
      @dropoff_latitude = dropoff_latitude
      @dropoff_longitude = dropoff_longitude
      @vehicle_type = vehicle_type
      # `normal` consents to another passenger sharing the car for a lower
      # fare; `premium` means the car is theirs.
      @service_tier = service_tier.presence || :normal
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

    # THE TARIFF IS A ROW, NOT FOUR SETTINGS, because it varies by vehicle and a
    # key-value table cannot hold that without 48 rows. `Setting` still owns the
    # scalars — the commission rate below is the same for every class, so it
    # stays a setting.
    def rate
      @rate ||= PricingRate.fetch(job_kind: Trip::JOB_KIND, audience: :customer,
                                  vehicle_type: @vehicle_type)
    end

    def fare
      @fare ||= (rate.amount_for(distance_km: distance_km, duration_minutes: duration_minutes) *
                 tier_multiplier).round(2)
    end

    # On a ride the uplift lifts BOTH sides, unlike a delivery: the fare is the
    # courier's revenue and we take a percentage of it, so a passenger paying
    # for exclusivity pays the driver more for it too. That is Model A's two
    # shapes rather than an inconsistency — see `DeliveryQuote#tier_multiplier`.
    def tier_multiplier
      return 1 unless @service_tier.to_s == "premium"

      Setting.fetch("premium_price_multiplier")
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
