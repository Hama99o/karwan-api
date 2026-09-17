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

    # `service_tier` is the customer's CONSENT, not a quality level: `normal`
    # is cheaper and agrees that the courier may combine this run with others,
    # `premium` buys the run outright. See SERVICE_TIERS_AND_BATCHING.md §1.
    def initialize(merchant:, items_total:, delivery_latitude:, delivery_longitude:,
                   service_tier: :normal)
      @merchant = merchant
      @items_total = BigDecimal(items_total.to_s)
      @delivery_latitude = delivery_latitude
      @delivery_longitude = delivery_longitude
      @service_tier = service_tier.presence || :normal
    end

    def call
      raise Error, "merchant has no location, so a delivery cannot be priced" if route.nil?

      Quote.new(
        distance_km: distance_km,
        duration_minutes: duration_minutes,
        route: route,
        # Frozen onto the order, because this is the number most likely to
        # have changed by the time somebody asks about it — that is its whole
        # purpose. `requested` rides along so a CAPPED fare is distinguishable
        # from an uncapped one, and an operator's mistyped 10 is findable.
        shortage_multiplier: shortage_multiplier,
        shortage_multiplier_requested: Pricing::ShortageMultiplier.requested,
        currency: Monetary::DEFAULT_CURRENCY,
        amounts: {
          items_total: @items_total,
          delivery_fee: delivery_fee,
          commission: commission,
          # v0: the courier keeps the whole delivery fee for the run itself.
          # They are separate columns, and separate settings, so the platform
          # can later take a cut of delivery without a migration — but taking
          # one now would mean paying couriers less than the customer already
          # believes they pay, and courier supply is the scarce side.
          #
          # THE TWO MULTIPLIERS LAND ON DIFFERENT SIDES, which is the whole of
          # the difference between them: a SHORTAGE is paid to the person
          # riding through it, while PREMIUM is the platform's (see
          # `tier_multiplier`). So this carries the first and not the second.
          courier_fee: courier_fee,
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

    # ── base → shortage → tier ────────────────────────────────────────────
    #
    # The customer's fee carries both multipliers; the courier's carries only
    # the shortage. Tier goes last so premium is always exactly +30% over the
    # same run, storm or no storm — the property that makes an upfront fare
    # explainable.
    def delivery_fee
      @delivery_fee ||= (courier_fee * tier_multiplier).round(2)
    end

    # What the courier is paid: the run, plus the shortage he rode through.
    def courier_fee
      @courier_fee ||= (base_delivery_fee * shortage_multiplier).round(2)
    end

    # Clamped so that shortage x tier cannot exceed `max_total_multiplier`.
    # Clamping HERE rather than on the customer's total is deliberate: capping
    # only the customer side would leave this uncapped, and the platform would
    # fund the gap. See Pricing::ShortageMultiplier.
    def shortage_multiplier
      @shortage_multiplier ||= Pricing::ShortageMultiplier.effective(tier: tier_multiplier)
    end

    def base_delivery_fee
      @base_delivery_fee ||= begin
        computed = Setting.fetch("delivery_base_fee") +
                   (Setting.fetch("delivery_fee_per_km") * BigDecimal(distance_km.to_s))

        # The floor is what makes a 200-metre order worth taking at all.
        [ computed, Setting.fetch("delivery_minimum_fee") ].max.round(2)
      end
    end

    # THE PREMIUM UPLIFT IS THE PLATFORM'S, on a delivery. What premium buys is
    # the capacity we hold empty for it, and the courier is paid for the run he
    # did — `courier_fee` comes from the courier rate for his vehicle and is
    # untouched by this.
    #
    # NOTE, and it is a real one for when batching ships: a premium job then
    # pays the courier the same as a normal one while forbidding him to combine
    # it, so couriers would prefer normal work and premium customers would wait
    # longest — backwards. The fix is to share the uplift with him at that
    # point, which is a number, not a redesign. Recorded in docs/NOTES.md.
    #
    # A RIDE behaves differently on purpose: there the fare IS the courier's
    # revenue and we take a percentage, so a premium fare lifts both sides. The
    # asymmetry is Model A's two shapes, not an oversight.
    def tier_multiplier
      return 1 unless ServiceTiers::ALL.key?(@service_tier.to_sym) && @service_tier.to_s == "premium"

      Setting.fetch("premium_price_multiplier")
    end

    # The merchant's own rate, not the global one — a deal struck with one
    # restaurant must not move everyone else.
    def commission
      @commission ||= @merchant.commission_on(@items_total)
    end
  end
end
