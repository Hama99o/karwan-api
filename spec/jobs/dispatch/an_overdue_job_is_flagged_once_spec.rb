require "rails_helper"

# ═══ AN OVERDUE JOB IS FLAGGED ONCE, NOT ONCE A MINUTE ══════════════════════
#
# `Dispatch::JobTimeoutsJob` runs every minute (`config/recurring.yml`) and
# `#flag!` wrote an `*.overdue` audit row on EVERY run for every job still past
# its timeout. Measured on the dev database, where the job only runs now and
# then: **784 of 935 audit rows** were these flags. In production, at one a
# minute, an order stuck three hours in `picked_up` writes ~180 of them.
#
# The audit log is the console page that answers *"who reassigned, who
# cancelled, who credited a wallet"* — one-way door 5. Burying the people's
# rows under the machine's is losing them in a different way.
#
# ── THE DISCRIMINATING INPUTS ─────────────────────────────────────────────
#
# - Several runs, minutes apart, over one stuck job → exactly one row.
# - The SAME job moving on and getting stuck again in a new state → a second
#   row, because that is a new fact a human needs. A fix that flagged a job
#   once for its whole life would pass the first example and fail this one.
# - A second job OF THE SAME KIND stuck at the same time → its own row, so
#   the "already flagged" test is per job and not per action.
RSpec.describe Dispatch::JobTimeoutsJob do
  def overdue_rows(job)
    AuditLog.where(action: "#{job.class.name.downcase}.overdue", target: job)
  end

  it "writes one row for a job however many runs find it still stuck" do
    order = create(:order, :preparing)
    order.update_columns(preparing_at: 3.hours.ago, updated_at: 3.hours.ago)

    4.times do
      described_class.new.perform
      travel 1.minute
    end

    expect(overdue_rows(order).count).to eq(1)
  end

  it "flags the same job again when it is stuck in a NEW state" do
    order = create(:order, :preparing)
    order.update_columns(preparing_at: 3.hours.ago, updated_at: 3.hours.ago)
    described_class.new.perform

    order.transition_to!(:ready, actor: nil, actor_role: :admin)
    travel Order::TIMEOUTS.fetch(:ready) + 1.minute
    2.times { described_class.new.perform }

    expect(overdue_rows(order).pluck(Arel.sql("details->>'status'"))).to eq(%w[preparing ready])
  end

  # Two ORDERS, not an order and a trip: the action name (`order.overdue` vs
  # `trip.overdue`) already separates those, so a mixed pair stayed green with
  # the per-job condition deleted — planted, and it did.
  it "flags each stuck job on its own" do
    first, second = create_list(:order, 2, :preparing)
    ride = create(:trip, :in_progress)
    [ first, second ].each { |o| o.update_columns(preparing_at: 3.hours.ago, updated_at: 3.hours.ago) }
    ride.update_columns(in_progress_at: 5.hours.ago, updated_at: 5.hours.ago)

    2.times { described_class.new.perform }

    expect([ first, second, ride ].map { |job| overdue_rows(job).count }).to eq([ 1, 1, 1 ])
  end
end
