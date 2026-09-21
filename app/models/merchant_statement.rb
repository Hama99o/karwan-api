# A shop's earnings for a period, as they were at the moment it was issued.
#
# R19: *"What they want is a statement: sales, commission deducted, net
# received."* Under Model A the answer to "how much do they owe us" is normally
# nothing — the courier pays them in cash at every pickup — so the statement is
# a record of what already happened rather than an invoice.
#
# NOTHING HERE IS RECOMPUTED. See the migration for why; the short version is
# that a statement recomputed on demand is silently rewritten by any later
# change to the calculation, and a merchant cannot reproduce the figure they
# were shown last month.
class MerchantStatement < ApplicationRecord
  include Monetary

  belongs_to :merchant

  validates :period_start, :period_end, :issued_at, presence: true
  validates :orders_count, numericality: { greater_than_or_equal_to: 0 }
  validate  :period_runs_forwards

  scope :newest_first, -> { order(period_start: :desc) }
  scope :for_period, ->(from, to) { where(period_start: from, period_end: to) }

  # The reconciliation this statement claims. Asserted in a spec rather than
  # enforced as a validation, because a statement that fails it must still be
  # STORED and visible — a figure that refuses to save is a figure nobody can
  # investigate, and the orders it came from are the evidence.
  def reconciles?
    net_received == items_total - commission
  end

  private

  def period_runs_forwards
    return if period_start.blank? || period_end.blank?
    return if period_end >= period_start

    errors.add(:period_end, "cannot be before period_start")
  end
end
