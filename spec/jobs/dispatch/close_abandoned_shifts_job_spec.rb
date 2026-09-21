require "rails_helper"

# ── A SHIFT NOBODY ENDED ───────────────────────────────────────────────────
#
# A courier whose app was killed never sends "off". The shift stays open and
# counts as capacity forever, which inflates the denominator in /admin/reports
# and makes utilisation look WORSE than it is — the opposite bias to the one
# `courier_shifts` exists to remove.
RSpec.describe Dispatch::CloseAbandonedShiftsJob do
  let(:courier) { create(:user, :courier) }
  let(:profile) { courier.courier_profile }

  def go_on_shift(at:, last_seen:)
    profile.update_column(:is_available, false)
    travel_to(at) { profile.set_availability!(true) }
    profile.update_column(:location_updated_at, last_seen)
  end

  it "closes a shift whose app has gone silent past the grace" do
    go_on_shift(at: 6.hours.ago, last_seen: 5.hours.ago)

    expect { described_class.perform_now }.to change { courier.courier_shifts.open_now.count }.from(1).to(0)
  end

  # ── IT ENDS WHEN THEY WENT QUIET, NOT WHEN WE NOTICED ──────────────────
  #
  # Closing at `now` would credit the courier with the silent hours and write
  # our sweep interval into the data — the report would then be measuring how
  # often this job runs.
  it "ends the shift at the last moment they were seen" do
    seen = 5.hours.ago
    go_on_shift(at: 6.hours.ago, last_seen: seen)

    described_class.perform_now

    shift = courier.courier_shifts.last
    expect(shift.ended_at).to be_within(2.seconds).of(seen)
    expect(shift.hours).to be_within(0.1).of(1.0), "the silent hours were counted as worked"
  end

  # An observed end and an inferred one must not read the same, or a report
  # quotes inference as evidence.
  it "marks the end as the system's, not the courier's" do
    go_on_shift(at: 6.hours.ago, last_seen: 5.hours.ago)

    described_class.perform_now

    expect(courier.courier_shifts.last.ended_by_system).to be(true)
  end

  it "leaves the switch and the history agreeing" do
    go_on_shift(at: 6.hours.ago, last_seen: 5.hours.ago)

    described_class.perform_now

    expect(profile.reload.is_available).to be(false),
                                           "the shift closed but the courier still reads as available"
  end

  # ── THE ONE THAT MATTERS MOST ──────────────────────────────────────────
  #
  # Dispatch refuses a courier whose position is older than 5 minutes, so a
  # courier idle for six minutes is already receiving no offers. Closing their
  # SHIFT on that basis would mark somebody who stepped into a building as
  # having gone home — and would destroy the idle-capacity data this table was
  # built to collect, which is its entire purpose.
  it "does NOT close a shift merely because dispatch would not offer to them" do
    go_on_shift(at: 2.hours.ago, last_seen: 10.minutes.ago)

    expect { described_class.perform_now }.not_to change { courier.courier_shifts.open_now.count }
    expect(profile.reload.is_available).to be(true)
  end

  it "closes at started_at when they never reported a position at all" do
    profile.update_column(:is_available, false)
    travel_to(6.hours.ago) { profile.set_availability!(true) }
    profile.update_column(:location_updated_at, nil)

    described_class.perform_now

    shift = courier.courier_shifts.last
    expect(shift.hours).to eq(0.0), "we never observed them, so nought observed hours is the honest reading"
  end

  it "leaves a shift that was properly ended alone" do
    go_on_shift(at: 6.hours.ago, last_seen: 5.hours.ago)
    profile.set_availability!(false)
    ended = courier.courier_shifts.last.ended_at

    described_class.perform_now

    expect(courier.courier_shifts.last.ended_at).to eq(ended)
    expect(courier.courier_shifts.last.ended_by_system).to be(false),
                                                          "a real toggle was relabelled as the system's inference"
  end

  it "is idempotent — a second run finds nothing" do
    go_on_shift(at: 6.hours.ago, last_seen: 5.hours.ago)
    described_class.perform_now

    expect(described_class.perform_now).to eq(0)
  end

  # The grace is admin-tunable per correction 13, so the job must read it
  # rather than carry a constant.
  it "honours the Setting rather than a hardcoded number" do
    go_on_shift(at: 3.hours.ago, last_seen: 90.minutes.ago)
    expect(described_class.perform_now).to eq(1), "90 minutes of silence is past the 30-minute default"

    other = create(:user, :courier)
    other.courier_profile.update_column(:is_available, false)
    travel_to(3.hours.ago) { other.courier_profile.set_availability!(true) }
    other.courier_profile.update_column(:location_updated_at, 90.minutes.ago)
    # `find_or_create_by` rather than `find_by!`: `Setting.fetch` falls back to
    # the definition's default when no row exists, so the code under test works
    # on an unseeded database and this example must too. Depending on seed state
    # would make it pass or fail for a reason that has nothing to do with the job.
    Setting.find_or_create_by!(key: "courier_shift_abandoned_after_minutes") { |s| s.value_type = :integer }
           .update!(value: "240")

    expect(described_class.perform_now).to eq(0), "the Setting was ignored"
  end
end
