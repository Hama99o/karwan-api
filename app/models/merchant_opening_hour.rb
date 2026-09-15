# Advisory only — `Merchant#is_open` is what decides whether orders are
# accepted. These exist so a closed merchant can show its next opening time.
class MerchantOpeningHour < ApplicationRecord
  # 0 = Sunday, matching Ruby's Time#wday. NOT the Afghan week, which starts
  # Saturday; display order is the client's problem, and storing anything but
  # wday means converting on every comparison.
  DAYS = (0..6).freeze

  belongs_to :merchant, inverse_of: :opening_hours

  validates :day_of_week, presence: true, inclusion: { in: DAYS }
  validates :opens_at, :closes_at, presence: true
  validate  :closes_after_opens

  private

  def closes_after_opens
    return if opens_at.blank? || closes_at.blank?
    return if closes_at > opens_at

    errors.add(:closes_at, "must be after opens_at")
  end
end
