module Couriers
  # How much of OUR money a courier is currently holding.
  #
  # This closes a gap where `cash_in_hand_limit` existed as a Setting, with a
  # description promising "above this a courier must settle before taking more
  # work", and nothing read it. A dead setting is worse than a missing one: it
  # reads as implemented.
  #
  # WHAT COUNTS, precisely, because the loose phrase "cash in hand" invites two
  # wrong readings:
  #
  #   NOT the gross cash they have touched. On a delivery they collect 500 and
  #   hand 350 straight to the merchant, so counting the gross would report
  #   exposure eight times larger than it is and block couriers for no reason.
  #
  #   NOT what they owe us in the wallet either. The wallet is a prepaid
  #   balance and a separate control — `can_fund?` guards the goods before a
  #   job; this guards the cash already collected after one.
  #
  #   It IS the platform's share of completed work whose money has not reached
  #   us: `commission` on every delivered order and completed ride still marked
  #   `collected`. That is exactly the sum a settlement is supposed to clear,
  #   and exactly what walks away if a courier does.
  #
  # Grouped by currency and never summed across it.
  class CashPosition
    def initialize(courier)
      @courier = courier
    end

    # { "AFN" => 350.0 }
    def by_currency
      totals = Hash.new(BigDecimal("0"))

      [ Order, Trip ].each do |klass|
        klass.for_courier(@courier)
             .where(payment_status: :collected)
             .group(:currency)
             .sum(:commission)
             .each { |currency, amount| totals[currency] += amount }
      end

      totals
    end

    def held(currency = Monetary::DEFAULT_CURRENCY)
      by_currency[currency]
    end

    # The settings row is denominated in AFN, so the comparison is made in AFN
    # only. A second currency will need its own limit rather than a conversion
    # — converting to compare is how a total ends up mixing currencies.
    def over_limit?
      held(Monetary::DEFAULT_CURRENCY) >= Setting.fetch("cash_in_hand_limit")
    end

    # ── EVERY COURIER OVER THE LIMIT, IN TWO QUERIES ─────────────────────
    #
    # The ops console's "who do I call in to settle" list. Computed in SQL over
    # both tables rather than by asking each wallet in turn, because the console
    # lists every courier and a per-row `CashPosition` would be one pair of
    # queries per row.
    #
    # THE SAME RULE AS `over_limit?`, deliberately — `held >= limit`, not `>`.
    # Two ways of asking one question is how a console disagrees with the
    # dispatcher about who may work, and there is a spec that puts couriers on
    # both sides of the limit AND exactly on it, then demands the two agree.
    #
    # `among:` narrows it to a set of couriers — dispatch's candidate pool, so
    # it asks once for the pool rather than twice per courier (24 Sept 2026).
    def self.over_limit_courier_ids(currency = Monetary::DEFAULT_CURRENCY, among: nil)
      limit = Setting.fetch("cash_in_hand_limit")
      totals = Hash.new(BigDecimal("0"))

      [ Order, Trip ].each do |klass|
        scope = klass.where(payment_status: :collected, currency: currency).where.not(courier_id: nil)
        scope = scope.where(courier_id: among) if among
        scope
             .group(:courier_id).sum(:commission)
             .each { |courier_id, amount| totals[courier_id] += amount }
      end

      totals.select { |_courier_id, held| held >= limit }.keys
    end

    # ── HOW LONG HE HAS BEEN HOLDING IT ─────────────────────────────────────
    #
    # `MONEY_AND_SETTLEMENT.md` §4 — *"warn, grace, then stop"* — runs on TIME,
    # and *"the app must warn him as the date approaches, not on the day."* The
    # limit above is about AMOUNT; nothing answered "since when". This is the
    # date a warning would count from: when the oldest cash he still holds was
    # collected — an order at delivery, a ride at completion. Nil when he holds
    # none. No deadline is computed here: the cycle and the grace are §4's
    # numbers and not yet set.
    COLLECTED_AT = { Order => :delivered_at, Trip => :completed_at }.freeze

    def held_since(currency = Monetary::DEFAULT_CURRENCY)
      COLLECTED_AT.filter_map { |klass, column|
        klass.for_courier(@courier).where(payment_status: :collected, currency: currency).minimum(column)
      }.min
    end

    def remaining_allowance
      [ Setting.fetch("cash_in_hand_limit") - held(Monetary::DEFAULT_CURRENCY), 0 ].max
    end
  end
end
