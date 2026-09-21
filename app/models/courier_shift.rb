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

  # ── CLOSING A SHIFT NOBODY ENDED ──────────────────────────────────────────
  #
  # A courier whose app was killed never sends "off", so the shift stays open
  # and counts as capacity forever — inflating the denominator and making
  # utilisation look WORSE than it is, the opposite bias to the one this table
  # was built to remove.
  #
  # ── WHY SILENCE IS THE SIGNAL, AND WHY NOT DISPATCH'S THRESHOLD ──────────
  #
  # An available courier's app reports position: `Dispatch::Eligibility` refuses
  # `:stale_location`, so a courier who stopped reporting is already receiving no
  # offers. Silence therefore means the app is gone.
  #
  # But `STALE_AFTER` is **5 minutes**, and closing a shift on that would mark a
  # courier who stepped inside a building as having gone home. Not being
  # dispatchable for six minutes and having ended your working day are different
  # facts. So the grace is its own `Setting`, defaulting to 30 minutes and
  # tunable without a deploy — correction 13 — because the right number depends
  # on how the app behaves on Afghan networks, which nobody has measured.
  #
  # ── IT ENDS WHEN THEY WENT QUIET, NOT WHEN WE NOTICED ────────────────────
  #
  # `location_updated_at` is the last moment we observed them. Closing at `now`
  # would credit them with the silent half hour and write our sweep interval
  # into the data. A courier who never reported at all is closed at
  # `started_at` — nought observed hours, which is the honest reading of "we
  # never saw them".
  def self.close_abandoned!(now: Time.current)
    grace = Setting.fetch("courier_shift_abandoned_after_minutes").to_i.minutes
    cutoff = now - grace

    open_now.includes(courier: :courier_profile).find_each.count do |shift|
      profile = shift.courier.courier_profile
      last_seen = profile&.location_updated_at
      next false if last_seen.present? && last_seen > cutoff

      ended = [ last_seen, shift.started_at ].compact.max
      transaction do
        shift.update!(ended_at: [ ended, shift.started_at ].max, ended_by_system: true)
        # The switch and the history must not disagree — that is the whole point
        # of the single entry point. `update_column` rather than the entry point
        # itself, because that would close the shift a second time at `now` and
        # overwrite the honest end with our sweep's clock.
        profile&.update_column(:is_available, false)
      end
      true
    end
  end

  private

  # EQUAL IS ALLOWED, and it carries meaning. A courier who toggled on and was
  # never seen again — no position report at all — is closed at `started_at` by
  # `close_abandoned!`, giving a zero-length shift. That is the honest record of
  # "they said they were available and we observed nothing", which is a
  # different fact from no shift at all, and deleting the row would destroy the
  # evidence that they tried.
  #
  # Only a shift ending BEFORE it began is impossible.
  def ends_after_it_starts
    return if ended_at.blank? || started_at.blank?
    return if ended_at >= started_at

    errors.add(:ended_at, "cannot be before started_at")
  end
end
