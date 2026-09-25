# Advisory only — `Merchant#is_open` is what decides whether orders are
# accepted. These exist so a closed merchant can show its next opening time.
#
# ── A WINDOW MAY CROSS MIDNIGHT (Hamma9901's ruling, 25 Sept 2026) ────────────
#
# "Open 18:00 to 01:00" is ordinary for a Kabul kebab house, more so in
# Ramadan, and was refused (`closes_after_opens`). The only workaround was to
# split one evening across two days' rows, which showed "closed at 00:00,
# opens at 00:00" on a shop that never shut.
#
# STORED IMPLICITLY: `closes_at` earlier than `opens_at` means the window
# closes the NEXT day. The row belongs to the day it OPENS: Monday 23:00-01:00
# is a Monday row. No flag in the table, because a stored flag is a second
# statement of the same fact and the two would drift. SERVED EXPLICITLY:
# serializers derive `closes_next_day` from the times, so no client infers it.
#
# Close equal to open is still refused: "twenty-four hours" and "zero hours"
# are the same input, and the shop means one of them.
#
# ── ONE CLOCK: MINUTES OF A WEEK THAT WRAPS ──────────────────────────────────
#
# Every question (is this moment inside a window? do two windows overlap?) is
# asked in minutes since Sunday 00:00, on a 7-day circle, so Saturday night
# into Sunday morning is the same case as Monday into Tuesday. The moment is
# read in Kabul (`Time.zone`), never in the process zone.
class MerchantOpeningHour < ApplicationRecord
  # 0 = Sunday, matching Ruby's Time#wday. NOT the Afghan week, which starts
  # Saturday; display order is the client's problem, and storing anything but
  # wday means converting on every comparison.
  DAYS = (0..6).freeze
  DAY = 24 * 60
  WEEK = 7 * DAY

  belongs_to :merchant, inverse_of: :opening_hours

  validates :day_of_week, presence: true, inclusion: { in: DAYS }
  validates :opens_at, :closes_at, presence: true
  validate  :opens_and_closes_at_different_times
  validate  :does_not_overlap_the_rest_of_the_week

  # Whether the posted week covers this moment, looking back into the
  # previous day's overnight window (00:30 on Tuesday is inside Monday's
  # 23:00-01:00).
  def self.covers?(rows, at)
    at = at.in_time_zone(Time.zone)
    minute = (at.wday * DAY) + (at.hour * 60) + at.min
    rows.any? { |row| row.contains?(minute) }
  end

  def closes_next_day?
    minutes(closes_at) < minutes(opens_at)
  end

  # [start, finish) in minutes since Sunday 00:00. `finish` may run past the
  # end of the week (Saturday 23:00-01:00), which `contains?` and `overlaps?`
  # read by also trying the other window a week along.
  def week_span
    start = (day_of_week * DAY) + minutes(opens_at)
    length = (minutes(closes_at) - minutes(opens_at)) % DAY
    [ start, start + length ]
  end

  def contains?(minute)
    start, finish = week_span
    [ minute, minute + WEEK ].any? { |m| m >= start && m < finish }
  end

  # Half-open: 09:00-14:00 and 14:00-18:00 touch and do not overlap, which
  # is what a shop that shuts for an afternoon and reopens writes.
  def overlaps?(other)
    a_start, a_finish = week_span
    b_start, b_finish = other.week_span
    [ -WEEK, 0, WEEK ].any? { |shift| a_start < b_finish + shift && b_start + shift < a_finish }
  end

  private

  def minutes(time) = (time.hour * 60) + time.min

  def opens_and_closes_at_different_times
    return if opens_at.blank? || closes_at.blank?
    return unless minutes(opens_at) == minutes(closes_at)

    errors.add(:closes_at, :same_open_and_close,
               message: "is the same as the opening time: say whether that is open all day or not at all")
  end

  # Across the whole week, not only the same day: once Monday's window can
  # run to 01:00, a Tuesday 00:30 row collides with it. Checked here, on the
  # model, because the console writes rows too and has no form-side guard.
  def does_not_overlap_the_rest_of_the_week
    return if opens_at.blank? || closes_at.blank? || day_of_week.blank? || merchant.nil?
    return if errors.any?

    siblings = merchant.opening_hours.where.not(id: id).to_a
    return unless siblings.any? { |other| overlaps?(other) }

    errors.add(:opens_at, :overlaps, message: "overlaps another window in this shop's week")
  end
end
