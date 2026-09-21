require "rails_helper"

# ── THE CONSOLE'S "WHO DO I CALL IN" LIST MUST AGREE WITH THE DISPATCHER ───
#
# `CashPosition#over_limit?` decides whether dispatch may offer a courier work.
# `CashPosition.over_limit_courier_ids` answers the same question for every
# courier at once, so the ops console can list them without two queries a row.
#
# Two ways of asking one question is how a console comes to disagree with the
# dispatcher about who may work. So this does not test the bulk version against
# a list I typed — it tests it against the SINGLE-COURIER RULE, with couriers on
# both sides of the limit **and exactly on it**.
#
# The boundary case is the one that matters and the one most easily missed: the
# rule is `held >= limit`, so a courier holding exactly the limit IS over. A
# test with only a clear-under and a clear-over courier cannot tell `>=` from
# `>` — the same hole that left the OTP expiry boundary untested for months.
RSpec.describe Couriers::CashPosition, ".over_limit_courier_ids" do
  let(:limit) { Setting.fetch("cash_in_hand_limit") }

  def courier_holding(amount)
    courier = create(:user, :courier)
    return courier if amount.zero?

    # `items_total` is DERIVED from the commission, not stated beside it: the
    # model refuses a negative `merchant_payout`, and a commission larger than
    # the food is a row the app could not produce. Stating 1000 here refused
    # every example above the limit — the invariant catching the fixture, which
    # is `docs/TESTING.md`'s fourth question doing its job.
    items_total = amount + 100

    create(:order, :with_items, :delivered, courier: courier, commission: amount,
                                            items_total: items_total,
                                            merchant_payout: items_total - amount,
                                            delivery_fee: 100, customer_total: items_total + 100,
                                            courier_fee: 100, payment_status: :collected)
    courier
  end

  it "agrees with the per-courier rule on every side of the limit" do
    under = courier_holding(limit - 1)
    exactly = courier_holding(limit)
    over = courier_holding(limit + 1)
    empty = courier_holding(0)

    ids = described_class.over_limit_courier_ids

    [ under, exactly, over, empty ].each do |courier|
      expect(ids.include?(courier.id)).to eq(described_class.new(courier).over_limit?),
                                          "the console and the dispatcher disagree about courier #{courier.id}"
    end
  end

  it "counts a courier exactly on the limit as over, because the rule is >=" do
    exactly = courier_holding(limit)

    expect(described_class.over_limit_courier_ids).to include(exactly.id)
    expect(described_class.new(exactly).over_limit?).to be(true)
  end

  it "leaves out a courier who has settled" do
    settled = courier_holding(limit + 100)
    Order.where(courier: settled).update_all(payment_status: Order.payment_statuses[:settled])

    expect(described_class.over_limit_courier_ids).not_to include(settled.id)
  end

  # Both demand types, because the pool is shared and the cash is one pocket.
  it "counts a ride's commission as well as a delivery's" do
    courier = create(:user, :courier)
    create(:trip, :completed, courier: courier, fare: limit + 120,
                              commission: limit + 100, courier_earnings: 20,
                              payment_status: :collected)


    expect(described_class.over_limit_courier_ids).to include(courier.id)
  end
end
