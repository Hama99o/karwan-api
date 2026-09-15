# PREPAID, never a debt.
#
# Couriers deposit credit, each completed job deducts our commission, and at the
# floor the app stops assigning work. We never chase anyone, because they cannot
# work without credit. Afghans understand this instantly: it is how phone credit
# works.
#
# `credit_line` is a small negative allowance so a new courier can start with
# nothing and a reconciliation delay never blocks them. Raising it with track
# record is what makes it a reason to stay.
#
# One wallet per person, across both demand types. This is where food and rides
# converge, and why Model A generalises: for food the courier advances the
# merchant payout and is left holding our commission; for a trip they keep the
# fare and owe commission from this balance. No advance to anybody on a ride.
class CourierWallet < ApplicationRecord
  include Monetary

  TOP_UP_CODE_LENGTH = 4

  belongs_to :user
  has_many :wallet_entries, dependent: :destroy

  validates :top_up_code, presence: true, uniqueness: true
  validates :balance, numericality: true
  validates :credit_line, numericality: { greater_than_or_equal_to: 0 }

  before_validation :assign_top_up_code, on: :create

  # How far below zero this courier may go. Stored positive, applied negative.
  def floor
    -credit_line
  end

  def available_credit
    balance - floor
  end

  # Can this courier be offered this job?
  #
  # TWO DIFFERENT GATES, and this used to be one — which was wrong. Each job
  # kind declares its own `wallet_requirement`:
  #
  #   delivery — the courier ADVANCES the merchant payout out of pocket, so the
  #              wallet must be able to float it. A 900 AFN order is not
  #              offerable to a nearly-empty wallet.
  #   ride     — nothing is advanced, so the requirement is zero and the only
  #              gate is that the wallet is not blocked.
  #
  # The consequence is deliberate and worth stating: a courier too short for a
  # delivery can still take a ride. Refusing them both would take income from
  # the side of the market whose supply is already scarce, for no reason.
  #
  # An earlier version gated both on the commission alone. That made every job
  # fundable by almost any wallet, which defeats the point of the gate — the
  # commission is what they end up OWING, not what they have to put up front.
  def can_fund?(job)
    return false unless job.currency == currency
    return false if blocked?

    balance - job.wallet_requirement >= floor
  end

  def blocked?
    balance <= floor
  end

  # Single entry point for every balance change, so no code path can move money
  # without leaving a ledger row saying who moved it.
  def record_entry!(kind:, amount:, recorded_by: nil, source: nil, note: nil)
    transaction do
      lock!
      new_balance = balance + amount
      entry = wallet_entries.create!(
        kind: kind, amount: amount, currency: currency, balance_after: new_balance,
        recorded_by: recorded_by, source: source, note: note
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
