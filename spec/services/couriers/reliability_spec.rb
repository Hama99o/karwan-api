require "rails_helper"

# ═══ WHAT THIS COURIER DID WITH THE WORK HE WAS SENT ═══════════════════════
#
# `TRUST_AND_REPUTATION.md` §5-A — *"a rider who cancels half his offers is
# gaming the queue"* — and §5-E — *"an unusually high cancellation rate for
# one driver, or the same driver-passenger pair cancelling repeatedly, both
# visible in data already collected."*
#
# ── THE DISCRIMINATING INPUTS ARE IN THIS FILE ON PURPOSE ─────────────────
#
# - A SUPERSEDED offer and a still-OPEN one, neither of which is his answer;
#   counting either would inflate the denominator.
# - An offer from before the window.
# - Another courier's offers and rides, so a count that forgot to scope fails.
# - A ride that failed BEFORE it started (a passenger no-show at the kerb): it
#   never had `in_progress_at` and is not a ride ended mid-way.
# - A passenger who appears once, beside one who appears twice, so the pair
#   rule is `> 1` and not "any passenger".
RSpec.describe Couriers::Reliability do
  let(:courier) { create(:user, :ride_courier) }
  let(:other) { create(:user, :ride_courier) }

  def offer(status, to: courier, at: 2.days.ago)
    create(:offer, courier: to, status: status, offered_at: at, expires_at: at + 1.minute)
  end

  def ended_mid_way(passenger, driver: courier)
    create(:trip, :in_progress, courier: driver, passenger: passenger)
      .tap { |t| t.update_columns(status: Trip.statuses[:failed], failure_reason: Trip.failure_reasons[:passenger_refused], failed_at: 1.day.ago) }
  end

  let(:twice) { create(:user, :customer) }
  let(:once) { create(:user, :customer) }

  before do
    3.times { offer(:accepted) }
    2.times { offer(:declined) }
    offer(:timed_out)
    offer(:superseded)
    offer(:offered, at: 10.seconds.ago)
    offer(:declined, at: 45.days.ago)
    offer(:declined, to: other)

    2.times { ended_mid_way(twice) }
    ended_mid_way(once)
    ended_mid_way(twice, driver: other)

    create(:trip, :arrived, courier: courier, passenger: once)
      .update_columns(status: Trip.statuses[:failed], failure_reason: Trip.failure_reasons[:passenger_no_show], failed_at: 1.day.ago)
  end

  subject(:figures) { described_class.for(courier) }

  it "counts his answers over the window, with his answers as the denominator" do
    expect(figures).to include(offers: 6, accepted: 3, declined: 2, timed_out: 1)
  end

  it "counts rides that started and did not finish, and not a no-show at the kerb" do
    expect(figures[:rides_ended_mid_way]).to eq(3)
  end

  it "names the passengers who appear in more than one of them" do
    expect(figures[:repeated_passengers]).to eq(twice.id => 2)
  end

  # At the layer where it lands: the operator's page, not the method.
  it "puts one line on the courier's console page, the recurring passenger named" do
    twice.update!(name: "Wahid Recurring")
    admin = AdminUser.create!(name: "Najibullah", email: "ops@karwan.af", password: "a-long-test-password")
    session = ActionDispatch::Integration::Session.new(Rails.application)
    session.post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
    session.get "/admin/courier_profiles/#{courier.courier_profile.id}"

    expect(session.response).to have_http_status(:ok)
    expect(CGI.unescapeHTML(session.response.body))
      .to include("6 offers answered: 3 taken, 2 declined, 1 let run out · " \
                  "3 rides ended mid-way — same passenger more than once: Wahid Recurring ×2")
  end

  it "says nothing about a courier who was sent nothing" do
    idle = described_class.for(create(:user, :ride_courier))

    expect(idle).to include(offers: 0, accepted: 0, declined: 0, timed_out: 0,
                            rides_ended_mid_way: 0, repeated_passengers: {})
  end
end
