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
  # ── THE LEDGER IS NOT A DEPENDENT, IT IS THE RECORD ──────────────────────
  #
  # `dependent: :destroy` here was a STATEMENT, and the statement was false: it
  # said destroying a wallet should destroy its ledger. One-way door 4 says the
  # opposite — *a balance can always be recomputed from entries; entries can
  # never be reconstructed from a balance* — so the honest answer to "delete
  # this wallet" is **no**.
  #
  # Changed for the documentation, not for defence in depth: nothing can reach
  # it today (no `destroy` route exists for wallets or users, asserted in
  # spec/requests/admin/delete_is_discard_spec.rb). But the next person reads
  # an association as permission, and that is exactly how the merchant console
  # button happened — the model said discard and the button said destroy. The
  # code should not assert something we would refuse.
  #
  # This also makes `User has_one :courier_wallet, dependent: :destroy`
  # truthful by consequence: destroying a courier who has ever been paid now
  # fails on the ledger rather than silently taking it with him.
  has_many :wallet_entries, dependent: :restrict_with_error

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
  # ── WRITTEN SUMMABLE ON PURPOSE (correction 19) ─────────────────────────────
  #
  # Multi-job is the next major feature, and batched, a courier advances the
  # SUM of two merchant payouts rather than one. `can_fund?(job)` taking a
  # single job is the exact shape that would have to change, so the arithmetic
  # is over a collection already — while the call sites stay `can_fund?(job)`,
  # because a set-based API today would be speculative generality.
  #
  # The requirement itself stays on the job (`wallet_requirement`), so batching
  # sums jobs rather than teaching this method about batches.
  def can_fund?(*jobs)
    jobs = jobs.flatten
    return false if blocked?
    return false if jobs.any? { |job| job.currency != currency }

    balance - jobs.sum { |job| job.wallet_requirement } >= floor
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
