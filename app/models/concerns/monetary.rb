# Included by every model that stores an amount.
#
# v0 is AFN-only, but the currency is stored explicitly on every row rather than
# assumed, because edu-safi shipped a total that added afghanis to dollars and
# the only reason that was possible is that the amounts did not carry their
# currency. Adding a second currency later must be a validation change here, not
# an archaeology exercise across twenty tables.
#
# The rule this exists to protect: NEVER sum across currencies. Group by it.
module Monetary
  extend ActiveSupport::Concern

  DEFAULT_CURRENCY = "AFN"
  SUPPORTED_CURRENCIES = [ DEFAULT_CURRENCY ].freeze

  # Afghan banknotes. Used only to advise what to BRING, never to compute a
  # charge.
  #
  # DESIGN.md's walkthrough asks for "have change for 500" under the cash
  # amount when the total is awkward, and AFGHAN_UX.md §6 gives the reason:
  # "people carry particular notes". A courier carries a change float; a
  # customer holding a 1,000 note for a 450 order is a doorstep argument.
  #
  # THE RULE LIVES HERE, NOT ON THE DEVICE. It was computed in the mobile app
  # for a while, which meant two things: the quote's own `suggested_notes`
  # field returned the total unchanged and was therefore useless, and a money
  # rule lived somewhere Hamma9900 could not change. Both serializers read this
  # now, so the cart and the status screen cannot disagree either.
  CHANGE_STEP = 500

  # What to bring, or nil when nothing needs saying.
  #
  # Quiet on a round hundred, because a courier's float covers hundreds.
  # Otherwise the next multiple of 500 — the note people actually carry — which
  # is 500 for a 450 total, exactly as the walkthrough says, and 1,500 for
  # 1,250, which a flat "have change for 500" got wrong.
  def self.change_advice(total)
    amount = total.to_d
    return nil if amount <= 0 || (amount % 100).zero?

    (amount / CHANGE_STEP).ceil * CHANGE_STEP
  end

  # How far the parts may miss the whole before a record is rejected: one minor
  # unit.
  #
  # It is not zero, and the reason is arithmetic rather than laziness. Money
  # columns are decimal(12,2), so each component is rounded to two places as it
  # is assigned. A percentage commission split across two fields therefore
  # rounds twice, and the two halves can each move by up to half a minor unit in
  # the same direction — 19.375 + 135.625 stores as 19.38 + 135.63 and sums to
  # 155.01 against a fare of 155. A tolerance of exactly one minor unit accepts
  # that and still rejects everything that matters: a missing component, a stale
  # fee, a discount nobody recorded.
  #
  # AFN has no subunit in practical circulation, so one minor unit of slack is
  # also invisible at the door.
  ROUNDING_TOLERANCE = 0.01

  included do
    validates :currency, presence: true, inclusion: { in: SUPPORTED_CURRENCIES }
  end
end
