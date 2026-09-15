# PREPAID, never a debt.
#
# Riders deposit credit, each delivered order deducts our commission, and at
# the floor the app stops assigning orders. We never chase anyone, because they
# cannot work without credit. Afghans understand this instantly: it is how
# phone credit works.
#
# `credit_line` is a small negative allowance so a new rider can start with
# nothing and a reconciliation delay never blocks them. Raising it with track
# record is what makes it a reason to stay.
class RiderWallet < ApplicationRecord
  include Monetary

  TOP_UP_CODE_LENGTH = 4

  belongs_to :user
  has_many :wallet_entries, dependent: :destroy

  validates :top_up_code, presence: true, uniqueness: true
  validates :balance, numericality: true
  validates :credit_line, numericality: { greater_than_or_equal_to: 0 }

  before_validation :assign_top_up_code, on: :create

  # How far below zero this rider may go. Stored positive, applied negative.
  def floor
    -credit_line
  end

  def available_credit
    balance - floor
  end

  # Can this rider fund an order? They advance the restaurant payout out of
  # pocket, but what the WALLET must cover is our commission — that is the only
  # money of ours they end up holding.
  def can_fund?(order)
    return false unless order.currency == currency

    balance - order.commission >= floor
  end

  def blocked?
    balance <= floor
  end

  # Single entry point for every balance change, so no code path can move money
  # without leaving a ledger row saying who moved it.
  def record_entry!(kind:, amount:, recorded_by: nil, order: nil, note: nil)
    transaction do
      lock!
      new_balance = balance + amount
      entry = wallet_entries.create!(
        kind: kind, amount: amount, currency: currency, balance_after: new_balance,
        recorded_by: recorded_by, order: order, note: note
      )
      update!(balance: new_balance)
      entry
    end
  end

  private

  # A 4-digit code, not a name. Names repeat and transliterate badly
  # (Muhammad / Mohammad / Mohammed); a code survives a bank statement.
  def assign_top_up_code
    self.top_up_code ||= loop do
      candidate = SecureRandom.random_number(10**TOP_UP_CODE_LENGTH)
                              .to_s.rjust(TOP_UP_CODE_LENGTH, "0")
      break candidate unless self.class.exists?(top_up_code: candidate)
    end
  end
end
