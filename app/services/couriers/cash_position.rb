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

    def remaining_allowance
      [ Setting.fetch("cash_in_hand_limit") - held(Monetary::DEFAULT_CURRENCY), 0 ].max
    end
  end
end
