# Append-only ledger row. Every balance change leaves one, and every one names
# who recorded it — a money row with no author is unauditable.
#
# Sign convention: `amount` is signed. A commission is negative, a top-up is
# positive, a reimbursement is positive, an adjustment is either.
class WalletEntry < ApplicationRecord
  include Monetary

  enum :kind, { commission: 0, top_up: 1, reimbursement: 2, adjustment: 3 }, prefix: true

  belongs_to :rider_wallet
  belongs_to :order, optional: true
  belongs_to :recorded_by, class_name: User.name, optional: true

  validates :amount, numericality: true
  validates :balance_after, numericality: true

  scope :chronological, -> { order(:created_at) }
  scope :newest_first,  -> { order(created_at: :desc) }

  # Never sum a mixed-currency relation. Group by it and let the caller decide
  # what to do with more than one group.
  def self.totals_by_currency
    group(:currency).sum(:amount)
  end
end
