module Pricing
  # Prices a delivery. Distance-based and deliberately simple.
  #
  # Hamma9900's instruction for v0, in his words: "we will do a simple
  # algorithm, we will test how many kilometers, like something like this, and
  # we will think how it works, we will see the market, and then we will check
  # if it's good." So: base + per-kilometre, floored at a minimum. No surge, no
  # zones, no bands, no time-of-day.
  #
  # Every input is a Setting row, so the market can be tested by editing numbers
  # rather than by deploying. When the real numbers arrive — what a Kabul
  # courier earns a day, what a customer will pay — they are typed into the
  # admin console, not into this file.
  #
  # THE AMOUNTS THIS RETURNS ARE SNAPSHOTS. The caller writes them onto the
  # order and the order keeps them forever. Changing a setting tomorrow must
  # never rewrite what somebody was charged today.
  class DeliveryQuote
    Error = Class.new(StandardError)

    def initialize(merchant:, items_total:, delivery_latitude:, delivery_longitude:)
      @merchant = merchant
      @items_total = BigDecimal(items_total.to_s)
      @delivery_latitude = delivery_latitude
      @delivery_longitude = delivery_longitude
    end

    def call
      raise Error, "merchant has no location, so a delivery cannot be priced" if route.nil?

      Quote.new(
        distance_km: distance_km,
        duration_minutes: duration_minutes,
        route: route,
        currency: Monetary::DEFAULT_CURRENCY,
        amounts: {
          items_total: @items_total,
          delivery_fee: delivery_fee,
          commission: commission,
          # v0: the courier keeps the whole delivery fee. They are separate
          # columns, and separate settings, so the platform can later take a cut
          # of delivery without a migration — but taking one now would mean
          # paying couriers less than the customer already believes they pay,
          # and courier supply is the scarce side.
          courier_fee: delivery_fee,
          merchant_payout: (@items_total - commission).round(2),
          customer_total: (@items_total + delivery_fee).round(2)
        }
      )
    end

    private

    # Routed when OSRM is reachable and enabled, straight-line otherwise —
    # never a failure. An order must not fall over because routing is down.
    def route
      return @route if defined?(@route)

      @route = Routing::DistanceResolver.new(
        from_lat: @merchant.latitude, from_lng: @merchant.longitude,
        to_lat: @delivery_latitude, to_lng: @delivery_longitude
      ).call
    end

    def distance_km
      route&.distance_km
    end

    # Travel time PLUS the kitchen. A customer waiting for food does not care
    # which half of the wait is cooking, and quoting only the ride makes every
    # order look late.
    #
    # The travel half comes from `eta_average_speed_kmh`, never from OSRM's own
    # duration — see Routing::DistanceResolver for why.
    def duration_minutes
      travel = route&.duration_minutes
      return nil if travel.nil?

      travel + (@merchant.effective_prep_time_minutes || 0)
    end

    def delivery_fee
      @delivery_fee ||= begin
        computed = Setting.fetch("delivery_base_fee") +
                   (Setting.fetch("delivery_fee_per_km") * BigDecimal(distance_km.to_s))

        # The floor is what makes a 200-metre order worth taking at all.
        [ computed, Setting.fetch("delivery_minimum_fee") ].max.round(2)
      end
    end

    # The merchant's own rate, not the global one — a deal struck with one
    # restaurant must not move everyone else.
    def commission
      @commission ||= @merchant.commission_on(@items_total)
    end
  end
end
