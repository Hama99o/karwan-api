require "rails_helper"

RSpec.describe Couriers::CashPosition do
  let(:courier) { create(:user, :courier) }

  subject(:position) { described_class.new(courier) }

  describe "#held" do
    it "is zero for a courier who has done nothing" do
      expect(position.held).to eq(0)
    end

    # Our exposure is the COMMISSION, not the gross cash they touched. On a
    # delivery they collect 500 and hand 350 straight to the merchant; counting
    # the gross would report exposure eight times larger and block couriers for
    # no reason.
    it "counts our commission, not the customer total" do
      create(:order, :delivered, courier: courier, commission: 50, customer_total: 500,
                                 items_total: 400, delivery_fee: 100, merchant_payout: 350)

      expect(position.held).to eq(50)
    end

    it "adds up across several collected jobs" do
      3.times { create(:order, :delivered, courier: courier, commission: 50) }

      expect(position.held).to eq(150)
    end

    # One pool, one exposure. A courier holding our money from rides and
    # deliveries is holding one pile of cash.
    it "counts rides and deliveries together" do
      create(:order, :delivered, courier: courier, commission: 50)
      create(:trip, :completed, courier: courier, fare: 160, commission: 20, courier_earnings: 140)

      expect(position.held).to eq(70)
    end

    it "ignores jobs already settled, which is the point of settling" do
      create(:order, :delivered, :settled, courier: courier, commission: 50)

      expect(position.held).to eq(0)
    end

    # Money not yet collected is not money in their hand.
    it "ignores jobs still in progress" do
      create(:order, :picked_up, courier: courier, commission: 50)

      expect(position.held).to eq(0)
    end

    it "ignores another courier's cash" do
      other = create(:user, :courier)
      create(:order, :delivered, courier: other, commission: 50)

      expect(position.held).to eq(0)
    end
  end

  describe "#by_currency" do
    # Never sum across currencies — group by it. v0 is AFN-only, which is
    # exactly when this is cheap to get right.
    it "groups rather than combining" do
      create(:order, :delivered, courier: courier, commission: 50)

      expect(position.by_currency).to eq({ "AFN" => 50 })
    end
  end

  describe "#over_limit?" do
    it "is false below the limit" do
      create(:order, :delivered, courier: courier, commission: 50)

      expect(position).not_to be_over_limit
    end

    # At the limit exactly, work stops. The boundary is where off-by-one lives.
    it "is true exactly at the limit" do
      Setting.seed_defaults!
      Setting.find_by!(key: "cash_in_hand_limit").update!(value: "100")
      create(:order, :delivered, courier: courier, commission: 100)

      expect(position).to be_over_limit
    end

    it "is true above the limit" do
      Setting.seed_defaults!
      Setting.find_by!(key: "cash_in_hand_limit").update!(value: "100")
      create(:order, :delivered, courier: courier, commission: 150)

      expect(position).to be_over_limit
    end

    it "clears once the cash is settled" do
      Setting.seed_defaults!
      Setting.find_by!(key: "cash_in_hand_limit").update!(value: "100")
      order = create(:order, :delivered, courier: courier, commission: 150)
      expect(position).to be_over_limit

      order.update!(payment_status: :settled, settled_at: Time.current)

      expect(described_class.new(courier)).not_to be_over_limit
    end
  end

  describe "#remaining_allowance" do
    it "is what they may still collect before settling" do
      create(:order, :delivered, courier: courier, commission: 50)

      expect(position.remaining_allowance).to eq(Setting.fetch("cash_in_hand_limit") - 50)
    end

    it "never goes negative, because a negative allowance is not actionable" do
      Setting.seed_defaults!
      Setting.find_by!(key: "cash_in_hand_limit").update!(value: "10")
      create(:order, :delivered, courier: courier, commission: 150)

      expect(position.remaining_allowance).to eq(0)
    end
  end
end
