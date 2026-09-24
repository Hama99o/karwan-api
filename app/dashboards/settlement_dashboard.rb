require "administrate/base_dashboard"

# Expected AND counted, both stored, plus the named person who counted.
# Mismatches are normal; unexplained mismatches are theft.
class SettlementDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    courier: Field::BelongsTo.with_options(class_name: "User"),
    expected_amount: Field::Number.with_options(decimals: 2),
    counted_amount: Field::Number.with_options(decimals: 2),
    currency: Field::String,
    counted_by_name: Field::String,
    counted_by: Field::BelongsTo.with_options(class_name: "User"),
    settled_at: Field::DateTime,
    # WHAT THE DEPOSIT COVERED: jobs collected up to this moment, from the
    # statement (`MONEY_AND_SETTLEMENT.md` §4). Nil on settlements recorded
    # before 24 Sept 2026, which covered everything up to `settled_at`.
    period_end: Field::DateTime,
    note: Field::Text,
    created_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[settled_at courier expected_amount counted_amount counted_by_name].freeze
  # `counted_by` is NOT shown: it references `users`, the person counting is
  # an operator or a bank statement, and nothing has ever written it — the name
  # is `counted_by_name`. An always-empty field reads as "nobody counted".
  SHOW_PAGE_ATTRIBUTES = %i[
    courier expected_amount counted_amount currency counted_by_name
    period_end settled_at note created_at
  ].freeze
  # A settlement is recorded through the named action on a wallet, which
  # computes `expected` from the unsettled jobs rather than trusting a typed
  # figure. Hand-editing it would let the two numbers agree by accident, which
  # is the one thing this table exists to prevent.
  FORM_ATTRIBUTES = [].freeze

  COLLECTION_FILTERS = {
    mismatched: ->(resources) { resources.mismatched }
  }.freeze

  def display_resource(settlement)
    "#{settlement.courier&.display_name} — #{settlement.settled_at&.to_date}"
  end
end
