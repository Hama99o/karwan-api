require "administrate/base_dashboard"

# A shop's earnings for a period, read-only.
#
# R19 makes these financial records shown to a partner, and R19's own
# recommendation is that they are SNAPSHOT when issued. An operator editing one
# would rewrite a figure a merchant has already been shown and cannot reproduce
# — the same reason the ledger and the shift log have no form either.
#
# If a statement is wrong, the orders behind it are the evidence and the fix is
# a correcting entry, not a quiet edit.
class MerchantStatementDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    merchant: Field::BelongsTo,
    period_start: Field::Date,
    period_end: Field::Date,
    currency: Field::String,
    orders_count: Field::Number,
    items_total: Field::Number.with_options(decimals: 2),
    commission: Field::Number.with_options(decimals: 2),
    net_received: Field::Number.with_options(decimals: 2),
    issued_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[merchant period_start period_end items_total commission net_received].freeze
  SHOW_PAGE_ATTRIBUTES = %i[
    merchant period_start period_end currency orders_count
    items_total commission net_received issued_at
  ].freeze
  FORM_ATTRIBUTES = [].freeze

  def display_resource(statement)
    "#{statement.merchant&.name} — #{statement.period_start} to #{statement.period_end}"
  end
end
