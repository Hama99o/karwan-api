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

  included do
    validates :currency, presence: true, inclusion: { in: SUPPORTED_CURRENCIES }
  end
end
