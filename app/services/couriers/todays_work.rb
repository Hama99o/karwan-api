module Couriers
  # ── THE COURIER'S "TODAY" SCREEN, WHICH HAD NO ENDPOINT ───────────────────
  #
  # `PRODUCT.md`'s Rider section: *"**Today** — deliveries, earnings, cash
  # currently in hand."* Every other screen in that section has an endpoint;
  # this one had none, and a courier finishing a shift could not answer what he
  # had earned without adding up wallet entries himself.
  #
  # ── BOTH DEMAND TYPES, NAMED SEPARATELY ───────────────────────────────────
  #
  # PRODUCT.md says "deliveries" because it was written when this was food-only.
  # Correction 9 settles it: one person, two job kinds, and the shared pool is
  # the whole business thesis. A courier who did three deliveries and two rides
  # did five jobs, and collapsing them would hide the half that `CLAUDE.md` says
  # the company turns on — *"two demand streams on one pool fill the idle
  # hours, which is the number the whole business turns on."*
  #
  # ── CASH IN HAND IS NOT A TODAY FIGURE, AND SAYING SO MATTERS ─────────────
  #
  # Deliveries and earnings are counted over today. **Cash in hand is a running
  # total** — it can include money collected yesterday and not yet settled. Put
  # under a heading that says "today" without qualification it would read as
  # "this is what I took today", and a courier reconciling his pocket against it
  # would come up short by exactly the amount he owes from yesterday.
  #
  # So it is returned beside the daily figures under its own name, from
  # `Couriers::CashPosition` — the SAME source the shift screen and the wallet
  # screen use, so three screens cannot disagree about what he is holding.
  class TodaysWork
    def initialize(courier, now: Time.current)
      @courier = courier
      @now = now
    end

    def call
      {
        from: day.begin,
        to: day.end,
        deliveries: deliveries.count,
        rides: rides.count,
        earnings: earnings_by_currency,
        # ── ONE SHAPE FOR MONEY THAT CAN BE MULTI-CURRENCY ────────────────
        #
        # An ARRAY of `{currency, amount}`, exactly as `earnings` above. The
        # first version served `CashPosition#by_currency` straight through —
        # a MAP keyed by currency — so one payload carried two different shapes
        # for the same idea and a client needed two parsers. Caught by capturing
        # the response as a fixture rather than describing it, which is the
        # whole argument for doing that.
        #
        # NOT a figure about today: it is what he is carrying right now, which
        # may include yesterday's uncollected money. The name says so.
        cash_in_hand_now: cash.by_currency.map { |currency, amount| { currency: currency, amount: amount } },
        # ── AND THE ONE DOCUMENTED EXCEPTION, WHICH IS A SCALAR ───────────
        #
        # The allowance is AFN-only BY DESIGN, not by omission:
        # `cash_in_hand_limit` is a `Setting` denominated in AFN and
        # `CashPosition#remaining_allowance` says so — *"the comparison is made
        # in AFN only. A second currency will need its own limit rather than a
        # conversion."* A figure that is definitionally single-currency is
        # honest as a scalar; wrapping it in a per-currency array would imply a
        # per-currency limit that does not exist.
        cash_allowance_remaining: cash.remaining_allowance
      }
    end

    private

    # Kabul's day, because `config.time_zone` is Kabul and `all_day` on a zoned
    # time cuts it where the courier lives rather than where the server does.
    def day = @now.in_time_zone.all_day

    def deliveries
      @deliveries ||= Order.where(courier: @courier, status: :delivered, delivered_at: day)
    end

    def rides
      @rides ||= Trip.where(courier: @courier, status: :completed, completed_at: day)
    end

    # Grouped by currency and never summed across it — one-way door 2.
    #
    # Each job's own frozen column, never recomputed: `courier_fee` on an order
    # and `courier_earnings` on a trip are what he was promised when he took it,
    # and a rate changed since must not rewrite what today says he earned.
    def earnings_by_currency
      from_orders = deliveries.group(:currency).sum(:courier_fee)
      from_trips = rides.group(:currency).sum(:courier_earnings)

      (from_orders.keys | from_trips.keys).map do |currency|
        {
          currency: currency,
          deliveries: from_orders[currency] || 0,
          rides: from_trips[currency] || 0,
          total: (from_orders[currency] || 0) + (from_trips[currency] || 0)
        }
      end
    end

    def cash
      @cash ||= Couriers::CashPosition.new(@courier)
    end
  end
end
