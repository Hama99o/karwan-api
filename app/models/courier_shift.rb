# A stretch of time a courier was available for work.
#
# Opened when they go on shift, closed when they go off. `ended_at` NULL means
# still on — which is why it is nullable rather than defaulted: "open" and
# "ended at the epoch" must never be the same value.
#
# WHY THIS EXISTS: `/admin/reports` can otherwise only divide by couriers who
# COMPLETED a job, so a courier who was online all day and took nothing is
# invisible and utilisation flatters the business. That is the wrong direction
# for a hiring decision, and the data cannot be recovered afterwards.
class CourierShift < ApplicationRecord
  belongs_to :courier, class_name: User.name

  validates :started_at, presence: true
  validate  :ends_after_it_starts

  scope :open_now, -> { where(ended_at: nil) }
  scope :newest_first, -> { order(started_at: :desc) }

  # Shifts that were open at any point inside the window. A shift that began
  # before the window and is still open counts, which is the common case for
  # "today".
  scope :overlapping, lambda { |from, to|
    where(started_at: ..to).where("ended_at IS NULL OR ended_at >= ?", from)
  }

  # ── AN OPEN SHIFT IS CAPPED AT `now`, NOT LEFT UNBOUNDED ─────────────────
  #
  # A courier whose app was killed never sends the "off" toggle, so their shift
  # stays open forever. Treating that as available-until-the-heat-death inflates
  # the denominator and would make utilisation look WORSE than it is — the
  # opposite bias to the one this table was built to remove, which would be a
  # poor trade.
  #
  # Capping at `now` is honest for a live shift and wrong for an abandoned one,
  # and there is no way to tell them apart from here. Recorded in
  # `docs/NOTES.md` as the known distortion, with the stale-shift closer named
  # as the fix rather than guessed at now.
  def hours(now: Time.current)
    finish = ended_at || now
    return 0.0 if finish <= started_at

    ((finish - started_at) / 1.hour).round(2)
  end

  private

  def ends_after_it_starts
    return if ended_at.blank? || started_at.blank?
    return if ended_at > started_at

    errors.add(:ended_at, "must be after started_at")
  end
end
