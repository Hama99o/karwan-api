# Append-only ledger row. Every balance change leaves one, and every one names
# who recorded it — a money row with no author is unauditable.
#
# Sign convention: `amount` is signed. A commission is negative, a top-up is
# positive, a reimbursement is positive, an adjustment is either.
#
# `source` is polymorphic over Order and Trip, since commission is owed on
# either. It is provenance only: the row carries its own amount, currency and
# balance_after, so a lost source degrades to "an entry whose job is unknown"
# rather than to wrong money. That self-containment is the only reason giving up
# the database foreign key is acceptable here.
class WalletEntry < ApplicationRecord
  include Monetary

  # `commission_topup` is OURS GIVING BACK, not the courier paying in — read it
  # as "a top-up OF his pay, funded from the commission", the opposite
  # direction from `top_up`, which is his own deposit. The sign says so too: a
  # positive entry against a negative `commission`.
  #
  # APPENDED AS 4, never by renumbering — these integers are in the database.
  enum :kind, { commission: 0, top_up: 1, reimbursement: 2, adjustment: 3, commission_topup: 4 },
       prefix: true

  belongs_to :courier_wallet
  belongs_to :source, polymorphic: true, optional: true
  belongs_to :recorded_by, class_name: User.name, optional: true

  # THE CONSOLE'S ACTOR LIVES IN A DIFFERENT TABLE. `recorded_by` is a `User`,
  # and correction 16 removed admin from the mobile app — so an operator's entry
  # had nothing valid to put there and every console-written row was anonymous
  # in the ledger. The audit log always knew; the ledger did not, and the ledger
  # is what a courier's statement is built from.
  belongs_to :recorded_by_admin_user, class_name: AdminUser.name, optional: true

  # Whoever they were. Used by the console and by anything reconciling a
  # statement, so neither has to know which table the actor came from.
  def recorded_by_name
    recorded_by_admin_user&.name || recorded_by&.name
  end

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
