require "administrate/base_dashboard"

class CourierWalletDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    user: Field::BelongsTo,
    top_up_code: Field::String,
    balance: Field::Number.with_options(decimals: 2),
    credit_line: Field::Number.with_options(decimals: 2),
    currency: Field::String,
    wallet_entries: Field::HasMany,
    created_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[top_up_code user balance credit_line currency].freeze
  SHOW_PAGE_ATTRIBUTES = %i[user top_up_code balance credit_line currency wallet_entries created_at].freeze
  # The credit line is the one field an operator sets directly — raising it
  # with track record is the design. The BALANCE is not editable: it is a
  # cached sum of the ledger, and typing over it would make the two disagree.
  # Money moves only through the named top-up and adjustment actions.
  FORM_ATTRIBUTES = %i[credit_line].freeze

  COLLECTION_FILTERS = {
    blocked: ->(resources) { resources.where("balance <= -credit_line") }
  }.freeze

  def display_resource(wallet)
    "#{wallet.user&.display_name} — #{wallet.top_up_code}"
  end
end
