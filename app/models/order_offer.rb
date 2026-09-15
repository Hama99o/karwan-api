# One dispatch offer to one rider, with a deadline.
#
# Dispatch is crude on purpose: nearest available rider whose wallet can fund
# the food, timeout, next rider, then hand to admin. No batching, no zones, no
# optimisation. The manual override is what makes the business operable while
# the automation is wrong.
class OrderOffer < ApplicationRecord
  DEFAULT_TTL = 60.seconds

  enum :status, { offered: 0, accepted: 1, declined: 2, timed_out: 3, superseded: 4 },
       prefix: true

  belongs_to :order, inverse_of: :offers
  belongs_to :rider, class_name: User.name

  validates :sequence, numericality: { greater_than: 0 }, uniqueness: { scope: :order_id }
  validates :offered_at, :expires_at, presence: true

  scope :pending,      -> { status_offered.where(expires_at: Time.current..) }
  scope :expired,      -> { status_offered.where(expires_at: ...Time.current) }
  scope :chronological, -> { order(:sequence) }

  def expired?
    status_offered? && expires_at <= Time.current
  end

  def respond!(status)
    update!(status: status, responded_at: Time.current)
  end
end
