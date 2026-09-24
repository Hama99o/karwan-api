require "rails_helper"

# ═══ HOW LONG A COURIER HAS HELD OUR CASH ═════════════════════════════════
#
# `MONEY_AND_SETTLEMENT.md` §4 — *"warn, grace, then stop"*, and *"the app must
# warn him as the date approaches, not on the day"* — runs on TIME. Everything
# built so far measured AMOUNT (`cash_in_hand_limit`); nothing could say since
# when. The operator enforcing §4 by hand needs "who has held our money
# longest", and the courier's app needs the date a warning counts from.
#
# Discriminating inputs: a SETTLED job older than everything (must not count),
# another courier's older cash (must not count), and a ride older than his
# oldest order (both job types, each by its own collection column).
RSpec.describe Couriers::CashPosition do
  let(:courier) { create(:user, :courier) }
  let(:merchant) { create(:merchant) }

  def delivered(at, courier: self.courier, payment_status: :collected)
    create(:order, :with_items, :delivered, merchant: merchant, courier: courier, commission: 50,
                                            payment_status: payment_status, delivered_at: at)
  end

  def completed_ride(at)
    create(:trip, :in_progress, courier: courier, fare: 150, commission: 30, courier_earnings: 120)
      .tap { |t| t.update_columns(status: Trip.statuses[:completed], payment_status: Trip.payment_statuses[:collected], completed_at: at) }
  end

  it "is when the oldest cash he still holds was collected, across both job types" do
    delivered(10.days.ago, payment_status: :settled)
    delivered(9.days.ago, courier: create(:user, :courier))
    delivered(3.days.ago)
    completed_ride(5.days.ago)

    expect(described_class.new(courier).held_since).to be_within(1.second).of(5.days.ago)
  end

  it "is nil when he holds nothing of ours" do
    delivered(2.days.ago, payment_status: :settled)

    expect(described_class.new(courier).held_since).to be_nil
  end

  it "moves forward when a deposit settles the older cash" do
    delivered(6.days.ago)
    delivered(1.day.ago)
    admin = AdminUser.create!(name: "Ops", email: "ops@karwan.af", password: "a-long-test-password")
    session = ActionDispatch::Integration::Session.new(Rails.application)
    session.post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
    session.post "/admin/courier_wallets/#{courier.courier_wallet.id}/settle",
                 params: { counted_amount: 50, counted_by_name: "Bank", deposited_at: 3.days.ago.strftime("%Y-%m-%dT%H:%M") }

    expect(described_class.new(courier).held_since).to be_within(1.minute).of(1.day.ago)
  end

  it "reaches the courier's wallet payload as a date" do
    delivered(4.days.ago)

    get_wallet = ActionDispatch::Integration::Session.new(Rails.application)
    get_wallet.get "/api/v1/courier/wallet", headers: { "Authorization" => "Bearer #{UserSession.issue!(courier).last}" }

    expect(Time.zone.parse(JSON.parse(get_wallet.response.body).dig("wallet", "cash_held_since")))
      .to be_within(1.second).of(4.days.ago)
  end
end
