require "administrate/base_dashboard"

class CourierWalletDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    user: Field::BelongsTo,
    top_up_code: Field::String,
    balance: Field::Number.with_options(decimals: 2),
    # Derived on the wallet, so Administrate reads the METHOD rather than a
    # column. Named for the money it describes, not for how it is obtained.
    cash_in_hand: Field::Number.with_options(decimals: 2),
    # When the oldest of that cash was collected — "who has held our money
    # longest" is the §4 question, and the amount alone cannot answer it.
    cash_held_since: Field::DateTime,
    credit_line: Field::Number.with_options(decimals: 2),
    currency: Field::String,
    wallet_entries: Field::HasMany,
    created_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[top_up_code user balance credit_line currency].freeze
  # `cash_in_hand` is DERIVED, not a column — the wallet asks `CashPosition`.
  # It is on the show page and NOT on the index: the index lists every wallet,
  # and a derived sum per row would be two queries a row. The `needs_settling`
  # filter below answers the index's version of the question in SQL instead.
  SHOW_PAGE_ATTRIBUTES = %i[user top_up_code balance cash_in_hand cash_held_since credit_line currency
                            wallet_entries created_at].freeze
  # The credit line is the one field an operator sets directly — raising it
  # with track record is the design. The BALANCE is not editable: it is a
  # cached sum of the ledger, and typing over it would make the two disagree.
  # Money moves only through the named top-up and adjustment actions.
  FORM_ATTRIBUTES = %i[credit_line].freeze

  COLLECTION_FILTERS = {
    blocked: ->(resources) { resources.where("balance <= -credit_line") },
    # ── WHO DO I CALL IN TO SETTLE ────────────────────────────────────────
    #
    # The other exposure control, and the other list. `blocked` is couriers who
    # cannot work because they owe us; this is couriers who must settle because
    # they are CARRYING too much of ours. A courier can be on this list with a
    # healthy balance, which is exactly why one filter cannot serve both.
    #
    # Resolved in SQL for every courier at once rather than per row.
    needs_settling: lambda { |resources|
      resources.where(user_id: Couriers::CashPosition.over_limit_courier_ids)
    }
  }.freeze

  def display_resource(wallet)
    "#{wallet.user&.display_name} — #{wallet.top_up_code}"
  end
end
