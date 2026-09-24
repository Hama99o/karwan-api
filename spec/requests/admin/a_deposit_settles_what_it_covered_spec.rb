require "rails_helper"

# ═══ A DEPOSIT SETTLES THE WORK IT COVERED, NOT THE WORK SINCE ═════════════
#
# `MONEY_AND_SETTLEMENT.md` §4: couriers settle **by bank deposit**, matched
# afterwards by their 4-digit code — *"deposited at the end of the week."* So
# the operator records a deposit some time after it was made, and the courier
# has usually kept working in between.
#
# `#settle` computed `expected` and marked settled EVERYTHING collected up to
# the moment the operator pressed it. Reproduced before this file existed —
# 250 deposited Friday, 150 more collected Saturday, recorded Sunday:
#
#   settlement: expected 400.0 counted 250.0 variance -150.0
#   platform thinks he holds: 0.0   (he actually holds 150 from Saturday)
#
# A courier who deposited exactly what he owed is recorded 150 SHORT — and
# `CLAUDE.md` says *"unexplained mismatches are theft"* — while the 150 he
# still holds is forgotten and his cash-in-hand gate is reset.
#
# Now the operator gives the deposit's time from the statement (`deposited_at`,
# defaulting to now), and a settlement covers what was collected up to it.
# Written to the settlement as `period_end`, a column that existed and that
# nothing wrote.
RSpec.describe "a deposit settles what it covered", type: :request do
  let(:admin) { AdminUser.create!(name: "Ops", email: "ops@karwan.af", password: "a-long-test-password") }
  let(:courier) { create(:user, :courier) }
  let(:merchant) { create(:merchant) }
  let(:friday_deposit) { Time.zone.parse("2026-09-18 18:00") }

  def delivered(at)
    create(:order, :with_items, :delivered, merchant: merchant, courier: courier, commission: 50,
                                            payment_status: :collected, delivered_at: at)
  end

  def completed_ride(at)
    # The fare must equal earnings plus commission; 30 of 150 keeps it valid.
    create(:trip, :in_progress, courier: courier, fare: 150, commission: 30, courier_earnings: 120)
      .tap { |t| t.update_columns(status: Trip.statuses[:completed], payment_status: Trip.payment_statuses[:collected], completed_at: at) }
  end

  before do
    5.times { |i| delivered(friday_deposit - (i + 1).hours) }
    completed_ride(friday_deposit - 30.minutes)
    3.times { |i| delivered(friday_deposit + 1.day - i.hours) }
    completed_ride(friday_deposit + 20.hours)

    travel_to friday_deposit + 2.days
    post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
  end

  def settle(**params)
    post "/admin/courier_wallets/#{courier.courier_wallet.id}/settle",
         params: { counted_amount: 280, counted_by_name: "Bank statement" }.merge(params)
  end

  it "expects only what was collected up to the deposit, across both job types" do
    settle(deposited_at: "2026-09-18T18:00")

    settlement = Settlement.last
    expect([ settlement.expected_amount, settlement.variance ]).to eq([ 280, 0 ])
    expect(settlement.period_end).to eq(friday_deposit)
  end

  it "leaves the work done since the deposit as cash he still holds" do
    settle(deposited_at: "2026-09-18T18:00")

    expect(Couriers::CashPosition.new(courier).held).to eq(180)
  end

  it "reads the time from the statement as Kabul time" do
    settle(deposited_at: "2026-09-18T18:00")

    expect(Settlement.last.period_end.utc).to eq(Time.utc(2026, 9, 18, 13, 30))
  end

  it "covers everything to now when no deposit time is given, as before" do
    settle

    expect(Settlement.last.expected_amount).to eq(460)
    expect(Couriers::CashPosition.new(courier).held).to eq(0)
  end

  it "refuses a deposit time in the future, which is a typo rather than a deposit" do
    settle(deposited_at: (Time.current + 1.day).iso8601)

    expect(Settlement.count).to eq(0)
    expect(Couriers::CashPosition.new(courier).held).to eq(460)
  end
end
