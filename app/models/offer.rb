# One dispatch offer, to one courier, with a deadline.
#
# Polymorphic over Order and Trip — dispatch is one system, and the question it
# asks is the same either way: is the nearest available courier, whose wallet
# can fund this job, willing to take it before the clock runs out?
#
# Kept crude on purpose: nearest available courier, timeout, next courier, then
# hand to admin. No batching, no optimisation, no zones. The manual override is
# what makes the business operable while the automation is wrong.
class Offer < ApplicationRecord
  DEFAULT_TTL = 60.seconds

  enum :status, { offered: 0, accepted: 1, declined: 2, timed_out: 3, superseded: 4 },
       prefix: true

  belongs_to :offerable, polymorphic: true
  belongs_to :courier, class_name: User.name

  validates :sequence, numericality: { greater_than: 0 },
                       uniqueness: { scope: [ :offerable_type, :offerable_id ] }
  validates :offered_at, :expires_at, presence: true

  scope :pending,       -> { status_offered.where(expires_at: Time.current..) }
  scope :expired,       -> { status_offered.where(expires_at: ...Time.current) }
  scope :chronological, -> { order(:sequence) }

  def expired?
    status_offered? && expires_at <= Time.current
  end

  def respond!(status)
    update!(status: status, responded_at: Time.current)
  end
end
