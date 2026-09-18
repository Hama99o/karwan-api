module Orders
  # ── A RANGE, BECAUSE A SINGLE MINUTE IS A PRECISE LIE ───────────────────────
  #
  # `docs/design/customer/order-tracking/SPEC.md`'s first decision, taken from
  # Glovo and quoted here because the shape of this class is that sentence:
  #
  #   "the arrival time is a RANGE — 13:30 – 13:40 — not a single minute. An
  #    honest interval beats a precise lie, and in Kabul traffic the interval is
  #    wide."
  #
  # Looked for a Hatiwal precedent first, per correction 15, and there is none:
  # `hatiwal-api` is a marketplace with no delivery leg, so nothing in its `app/`
  # mentions an ETA or an arrival. This is the "genuinely new" half of the honest
  # boundary in CLAUDE.md — but only in its arithmetic. Every input it reads
  # already exists: `Geo::Distance.travel_minutes`, the frozen `distance_km`, the
  # per-transition timestamps, and the courier's reported position.
  #
  # ── WHAT MAKES THE INTERVAL HONEST, AND IT IS NOT A FIXED WIDTH ────────────
  #
  # **The width reflects what we do not know.** Before a courier is assigned, the
  # ride to the shop is a guess about a person who does not exist yet, so the
  # window is wide. Once he is moving and reporting, both legs are measured from
  # where he actually is, and it narrows. A fixed ±10 minutes would be equally
  # confident about both, which is the precise lie wearing a range.
  #
  # ── WHAT IT DELIBERATELY DOES NOT DO ───────────────────────────────────────
  #
  # It never re-measures the merchant→customer leg. That distance was frozen on
  # the order at quote time and the FARE was computed from it; MAP_AND_ROUTING.md
  # requires a fare be explainable later, and an explanation that re-measures is
  # not an explanation of what was charged. So the arrival window and the price
  # are answers about the same journey.
  class ArrivalWindow
    # `basis` is carried out rather than inferred by the client, because "is this
    # measured or assumed" is exactly the thing an app would otherwise guess at.
    Window = Struct.new(:from, :to, :basis, keyword_init: true)

    ROUNDING_MINUTES = 5

    def self.for(order, now: Time.current) = new(order, now: now).call

    def initialize(order, now: Time.current)
      @order = order
      @now = now
    end

    def call
      # A delivered, cancelled, rejected or failed order has no arrival. Same
      # rule `merchant_phone` follows — the app already branches on `is_live`
      # and this agrees with it rather than asking the client to enforce it.
      return nil if @order.terminal?

      minutes = remaining_minutes
      return nil if minutes.nil?

      spread = spread_minutes(minutes)

      Window.new(
        # Clamped at `now`: a window that opens in the past reads as already late
        # on a courier who is simply close.
        from: round_down(@now + [ minutes - spread, 0 ].max.minutes),
        to: round_up(@now + (minutes + spread).minutes),
        basis: measured? ? "measured" : "assumed"
      )
    end

    private

    # ── THE LEGS THAT ARE STILL AHEAD, WHICH DEPENDS ON THE STATE ─────────────
    #
    # Once the food is in the bag the kitchen and the ride to the shop are spent,
    # and only the last leg remains. Summing all three at every state is how an
    # ETA stops moving when the courier does.
    def remaining_minutes
      last_leg = delivery_leg_minutes
      return nil if last_leg.nil?
      return last_leg if @order.picked_up_at.present?

      kitchen_minutes + approach_minutes + last_leg
    end

    def delivery_leg_minutes
      if @order.picked_up_at.present? && courier_coordinates
        from_courier = Geo::Distance.km(
          from_lat: courier_coordinates[0], from_lng: courier_coordinates[1],
          to_lat: @order.delivery_latitude, to_lng: @order.delivery_longitude
        )
        return Geo::Distance.travel_minutes(from_courier)
      end

      Geo::Distance.travel_minutes(@order.distance_km)
    end

    # How long until the food is ready. `ready_at` is the fact; everything before
    # it is the shop's own estimate counting down from when it started cooking.
    def kitchen_minutes
      return 0 if @order.ready_at.present?

      prep = @order.merchant&.effective_prep_time_minutes.to_i
      started = @order.preparing_at || @order.accepted_at
      # Not yet accepted: nobody has started, so the whole prep time is ahead.
      return prep if started.nil?

      [ prep - ((@now - started) / 60).floor, 0 ].max
    end

    # The courier's ride TO the shop. Measured when he is assigned and reporting;
    # otherwise a tunable stand-in, because "zero" would quietly claim a courier
    # is already at the counter.
    def approach_minutes
      if courier_coordinates && @order.merchant
        measured = Geo::Distance.travel_minutes(
          Geo::Distance.km(
            from_lat: courier_coordinates[0], from_lng: courier_coordinates[1],
            to_lat: @order.merchant.latitude, to_lng: @order.merchant.longitude
          )
        )
        return measured unless measured.nil?
      end

      Setting.fetch("eta_courier_approach_minutes").to_i
    end

    def spread_minutes(minutes)
      key = measured? ? "eta_window_spread_percent" : "eta_window_spread_percent_unassigned"
      percent = Setting.fetch(key).to_f

      [ (minutes * percent / 100.0).ceil, minimum_spread ].max
    end

    # The floor, halved because it is applied to each side. A two-minute window
    # is the precise lie this class exists to refuse, however confident the
    # arithmetic feels.
    def minimum_spread = (Setting.fetch("eta_window_minimum_minutes").to_f / 2).ceil

    def measured? = courier_coordinates.present?

    def courier_coordinates
      return @courier_coordinates if defined?(@courier_coordinates)

      profile = @order.courier&.courier_profile
      # Both conditions, exactly as `Customers::TrackSerializer` reads them: a
      # stale timestamp is where he used to be, and that is not a measurement.
      @courier_coordinates =
        if profile&.location_fresh? && profile.coordinates.present?
          profile.coordinates
        end
    end

    # Rounded outward to five minutes, which is how a person reads an estimate.
    # "13:30 – 13:40" is believed as an estimate; "13:28 – 13:41" claims an
    # accuracy no straight-line ETA has.
    def round_down(time) = Time.zone.at((time.to_i / (ROUNDING_MINUTES * 60)) * ROUNDING_MINUTES * 60)
    def round_up(time) = Time.zone.at(((time.to_i + (ROUNDING_MINUTES * 60) - 1) / (ROUNDING_MINUTES * 60)) * ROUNDING_MINUTES * 60)
  end
end
