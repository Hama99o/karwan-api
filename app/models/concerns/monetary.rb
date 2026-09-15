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
