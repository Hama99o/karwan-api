require "rails_helper"

# ── DISPATCH ASKS "WHO IS BUSY?" ONCE, AND GETS THE SAME ANSWERS ────────────
#
# Measured 24 Sept 2026: `carrying_another_job?` ran two queries per candidate
# courier — 171 for 95 couriers, ~400 at 200 — inside the job's row lock and
# the shop's Accept request. `Eligibility.busy_courier_ids` asks once for the
# pool. The whole value is that NOTHING about the decision changes, so the
# first example compares every verdict, per courier, both ways.
RSpec.describe "dispatch asks who is busy once for the whole pool" do
  let(:merchant) { create(:merchant, latitude: 34.5553, longitude: 69.2075) }
  let(:job) do
    create(:order, :with_items, :accepted, merchant: merchant, customer_total: 500, commission: 50,
                                           courier_fee: 100, merchant_payout: 350)
  end

  def courier(offset)
    create(:user, :courier).tap do |c|
      c.courier_profile.update!(is_available: true, accepted_job_kinds: %w[delivery ride],
                                last_latitude: 34.5553 + offset, last_longitude: 69.2075,
                                location_updated_at: Time.current)
      c.courier_wallet.update!(balance: 5_000, credit_line: 500)
    end
  end

  # One of each case the rule tells apart.
  let!(:pool) do
    free = courier(0.001)
    on_an_order = courier(0.002).tap { |c| create(:order, :with_items, :picked_up, merchant: merchant, courier: c) }
    on_a_trip = courier(0.003).tap { |c| create(:trip, :accepted, courier: c) }
    finished = courier(0.004).tap { |c| create(:order, :with_items, :delivered, merchant: merchant, courier: c) }
    { free: free, on_an_order: on_an_order, on_a_trip: on_a_trip, finished: finished }
  end

  def verdicts(batched:)
    busy = Dispatch::Eligibility.busy_courier_ids(pool.values.map(&:id), job: job) if batched
    pool.transform_values { |c| Dispatch::Eligibility.new(courier: c.reload, job: job, busy_courier_ids: busy).reason }
  end

  it "reaches exactly the verdict the per-courier question reached, for every courier" do
    expect(verdicts(batched: true)).to eq(verdicts(batched: false))
    expect(verdicts(batched: true)).to include(on_an_order: :already_on_a_job, on_a_trip: :already_on_a_job)
    expect(verdicts(batched: true)[:free]).not_to eq(:already_on_a_job)
    expect(verdicts(batched: true)[:finished]).not_to eq(:already_on_a_job)
  end

  it "does not count the job being dispatched against the courier who holds it" do
    holder = pool[:free]
    job.update!(courier: holder)

    expect(Dispatch::Eligibility.busy_courier_ids([ holder.id ], job: job)).not_to include(holder.id)
  end

  # What THIS change guarantees: the live-job question is not asked per
  # courier, and the pooled pair runs once. (Other checks still query per
  # eligible courier — the cash position and settings reads — measured and
  # recorded in docs/NOTES.md, not changed here.)
  it "asks the live-job question once for the pool, never per courier" do
    5.times { |i| courier(0.01 + (i * 0.001)) }
    seen = []
    counter = ->(*, payload) { seen << payload[:sql] unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { Dispatch::OfferService.new(job).blocked_reason }

    per_courier = seen.grep(/FROM "(orders|trips)" WHERE .*"status" NOT IN .*"courier_id" = /)
    pooled = seen.grep(/SELECT DISTINCT "(orders|trips)"."courier_id"/)

    expect(per_courier).to be_empty
    expect(pooled.size).to eq(2)
  end
end
