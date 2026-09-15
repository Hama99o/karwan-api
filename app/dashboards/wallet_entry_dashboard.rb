require "administrate/base_dashboard"

# The ledger, read-only. A balance can be recomputed from entries; entries can
# never be reconstructed from a balance, so nothing here is editable.
class WalletEntryDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    courier_wallet: Field::BelongsTo,
    kind: Field::String,
    amount: Field::Number.with_options(decimals: 2),
    balance_after: Field::Number.with_options(decimals: 2),
    currency: Field::String,
    source_type: Field::String,
    source_id: Field::Number,
    recorded_by: Field::BelongsTo.with_options(class_name: "User"),
    note: Field::Text,
    created_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[created_at courier_wallet kind amount balance_after].freeze
  SHOW_PAGE_ATTRIBUTES = %i[
    courier_wallet kind amount balance_after currency source_type source_id
    recorded_by note created_at
  ].freeze
  FORM_ATTRIBUTES = [].freeze

  def display_resource(entry)
    "#{entry.kind} #{entry.amount}"
  end
end
