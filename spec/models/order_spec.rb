require "rails_helper"

RSpec.describe Order, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:customer_phone) }

    it "generates a unique code on create so support can read it out loud" do
      order = create(:order)

      expect(order.code).to match(/\AK\d{10}\z/)
    end

    it "rejects a delivery pin outside real coordinates" do
      expect(build(:order, delivery_latitude: 91)).not_to be_valid
      expect(build(:order, delivery_longitude: -181)).not_to be_valid
    end

    it "requires a currency it recognises" do
      expect(build(:order, currency: "USD")).not_to be_valid
    end

    describe "#totals_add_up" do
      it "accepts the brief's worked example" do
        order = build(:order, food_total: 400, delivery_fee: 100, customer_total: 500)

        expect(order).to be_valid
      end

      # This is the check that stops an order whose total nobody can explain at
      # the door. Planting the bug to prove the check can fail.
      it "rejects a customer_total that is not food_total + delivery_fee" do
        order = build(:order, food_total: 400, delivery_fee: 100, customer_total: 450)

        expect(order).not_to be_valid
        expect(order.errors[:customer_total].join).to include("500")
      end

      it "tolerates sub-afghani rounding" do
        order = build(:order, food_total: 400.004, delivery_fee: 100, customer_total: 500)

        expect(order).to be_valid
      end
    end

    it "rejects negative money" do
      expect(build(:order, commission: -1)).not_to be_valid
    end
  end

  describe "the state machine" do
    it "declares a transition table covering every status" do
      expect(described_class::TRANSITIONS.keys.map(&:to_s).sort)
        .to eq(described_class::STATUSES.keys.map(&:to_s).sort)
    end

    it "gives every non-terminal state a timeout" do
      expect(described_class.states_without_timeout).to be_empty
    end

    # The class-level fix for the bug this spec found: TRANSITIONS listed
    # `:merchant`, which is not a role, so every merchant transition
    # silently returned false and the merchant could not accept its own
    # orders. Worse, the "customer cannot accept" example passed anyway —
    # vacuously, because no role matched. This guard makes the whole table
    # checkable rather than relying on someone writing an example per cell.
    it "names only real roles, in every cell of the table" do
      named_roles = described_class::TRANSITIONS.values.flat_map(&:values).flatten.uniq

      expect(named_roles - Roles::ALL.keys).to be_empty,
        "TRANSITIONS names roles that do not exist: #{(named_roles - Roles::ALL.keys).inspect}"
    end

    it "names only real statuses, in every cell of the table" do
      named_statuses = described_class::TRANSITIONS.values.flat_map(&:keys).uniq

      expect(named_statuses - described_class::STATUSES.keys.map(&:to_sym)).to be_empty
    end

    it "leaves every terminal state with no way out" do
      described_class::TERMINAL.each do |status|
        expect(described_class::TRANSITIONS[status]).to eq({}), "#{status} should be terminal"
      end
    end

    describe "#can_transition_to?" do
      it "lets the merchant accept a placed order" do
        expect(build(:order, status: :placed).can_transition_to?(:accepted, actor_role: :merchant_owner)).to be true
      end

      it "does not let the customer accept their own order" do
        expect(build(:order, status: :placed).can_transition_to?(:accepted, actor_role: :customer)).to be false
      end

      it "lets the customer cancel while the order is only placed" do
        expect(build(:order, status: :placed).can_transition_to?(:cancelled, actor_role: :customer)).to be true
      end

      # Once the food is being cooked the customer cannot cancel — somebody has
      # already spent money on it.
      it "does not let the customer cancel once the kitchen has started" do
        expect(build(:order, status: :preparing).can_transition_to?(:cancelled, actor_role: :customer)).to be false
      end

      it "refuses a jump from placed straight to delivered, for anyone including admin" do
        order = build(:order, status: :placed)

        expect(order.can_transition_to?(:delivered, actor_role: :admin)).to be false
        expect(order.can_transition_to?(:delivered, actor_role: :rider)).to be false
      end

      it "refuses any transition out of a terminal state" do
        expect(build(:order, status: :delivered).can_transition_to?(:cancelled, actor_role: :admin)).to be false
      end
    end

    describe "#terminal?" do
      it "is true for the four end states and false for the rest" do
        described_class::TERMINAL.each do |status|
          expect(build(:order, status: status)).to be_terminal
        end
        expect(build(:order, status: :preparing)).not_to be_terminal
      end
    end
  end

  describe "#overdue?" do
    it "is false for an order that has just been placed" do
      expect(create(:order)).not_to be_overdue
    end

    it "is true once the state's timeout has passed" do
      expect(create(:order, :overdue)).to be_overdue
    end

    # A delivered order is not late, it is finished. Colouring it red on the
    # admin board would bury the orders that actually need attention.
    it "is false for a terminal state, which has no timeout" do
      expect(create(:order, :delivered)).not_to be_overdue
    end
  end

  describe "#state_entered_at" do
    it "uses the timestamp of the current state" do
      order = create(:order, :accepted)

      expect(order.state_entered_at).to be_within(2.seconds).of(order.accepted_at)
    end

    it "falls back to updated_at when the state has no column" do
      order = create(:order)
      order.update_columns(placed_at: nil)

      expect(order.reload.state_entered_at).to be_present
    end
  end

  describe "the Model A money identities" do
    let(:order) { create(:order) }

    it "hands the merchant the food less our commission" do
      expect(order.courier_advance).to eq(350)
      expect(order.food_total - order.commission).to eq(order.merchant_payout)
    end

    it "leaves the courier holding exactly our commission, which is our whole exposure" do
      expect(order.platform_cash_held).to eq(50)
    end

    it "reconciles from the courier's side: collected - advanced - fee == our commission" do
      expect(order.customer_total - order.merchant_payout - order.courier_fee).to eq(order.commission)
    end
  end

  describe "enums" do
    it "makes payment_status an explicit three-state column, never derived" do
      expect(described_class.payment_statuses.keys).to eq(%w[pending collected settled])
    end

    it "offers only cash in v0" do
      expect(described_class.payment_methods.keys).to eq(%w[cash])
    end

    it "gives the merchant a fixed reason list to reject with" do
      expect(described_class.rejection_reasons.keys).to eq(%w[out_of_stock too_busy closing other])
    end
  end

  describe "scopes" do
    describe ".live" do
      it "excludes every terminal state" do
        live = create(:order, :preparing)
        create(:order, :delivered)
        create(:order, :cancelled)
        create(:order, :failed)

        expect(described_class.live).to contain_exactly(live)
      end
    end

    describe ".unsettled" do
      it "is every order whose money has not reached us" do
        pending_order = create(:order)
        collected = create(:order, :delivered)
        create(:order, :delivered, :settled)

        expect(described_class.unsettled).to contain_exactly(pending_order, collected)
      end
    end
  end
end
