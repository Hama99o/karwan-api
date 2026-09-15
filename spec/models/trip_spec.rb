require "rails_helper"

RSpec.describe Trip, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:passenger_phone) }

    it "generates a T-prefixed code, distinguishable from an order's K" do
      expect(create(:trip).code).to match(/\AT\d{10}\z/)
      expect(create(:order).code).to match(/\AK\d{10}\z/)
    end

    it "requires both pins" do
      expect(build(:trip, pickup_latitude: nil)).not_to be_valid
      expect(build(:trip, dropoff_longitude: nil)).not_to be_valid
    end

    it "rejects coordinates that are not on Earth" do
      expect(build(:trip, pickup_latitude: 91)).not_to be_valid
      expect(build(:trip, dropoff_longitude: 181)).not_to be_valid
    end

    describe "#fare_splits_correctly" do
      it "accepts a fare that splits into commission plus courier earnings" do
        expect(build(:trip, fare: 200, commission: 25, courier_earnings: 175)).to be_valid
      end

      # Planting the bug to prove the check can fail: money that does not add up
      # must not be storable.
      it "rejects a split that does not reconstitute the fare" do
        trip = build(:trip, fare: 200, commission: 25, courier_earnings: 100)

        expect(trip).not_to be_valid
        expect(trip.errors[:courier_earnings].join).to include("200")
      end

      # decimal(12,2) rounds each component on assignment, so 19.375 and
      # 135.625 store as 19.38 and 135.63 and sum to 155.01 against a fare of
      # 155. One minor unit of slack is exactly what that costs.
      it "tolerates the one-minor-unit drift that a percentage split produces" do
        trip = build(:trip, fare: 155, commission: 19.375, courier_earnings: 135.625)

        expect(trip.commission).to eq(BigDecimal("19.38"))
        expect(trip.courier_earnings).to eq(BigDecimal("135.63"))
        expect(trip).to be_valid
      end

      it "still rejects drift larger than one minor unit" do
        expect(build(:trip, fare: 155, commission: 19.38, courier_earnings: 135.65)).not_to be_valid
      end
    end
  end

  describe "the state machine" do
    it "names only real roles and statuses in every cell" do
      named_roles = described_class::TRANSITIONS.values.flat_map(&:values).flatten.uniq
      named_statuses = described_class::TRANSITIONS.values.flat_map(&:keys).uniq

      expect(named_roles - Roles::ALL.keys).to be_empty
      expect(named_statuses - described_class::STATUSES.keys.map(&:to_sym)).to be_empty
    end

    it "covers every status and gives every non-terminal state a timeout" do
      expect(described_class::TRANSITIONS.keys.map(&:to_s).sort)
        .to eq(described_class::STATUSES.keys.map(&:to_s).sort)
      expect(described_class.states_without_timeout).to be_empty
    end

    it "leaves every terminal state with no way out" do
      described_class::TERMINAL.each do |status|
        expect(described_class::TRANSITIONS[status]).to eq({}), "#{status} should be terminal"
      end
    end

    it "lets a courier accept, arrive, start and complete" do
      trip = build(:trip)

      expect(trip.can_transition_to?(:accepted, actor_role: :courier)).to be true
      expect(build(:trip, status: :accepted).can_transition_to?(:arrived, actor_role: :courier)).to be true
      expect(build(:trip, status: :arrived).can_transition_to?(:in_progress, actor_role: :courier)).to be true
      expect(build(:trip, status: :in_progress).can_transition_to?(:completed, actor_role: :courier)).to be true
    end

    # A passenger who has been picked up cannot un-book the ride they are
    # sitting in. Cancelling is for before the trip starts.
    it "does not let the passenger cancel once the trip is under way" do
      expect(build(:trip, status: :in_progress).can_transition_to?(:cancelled, actor_role: :customer)).to be false
    end

    it "lets the passenger cancel while nobody has come yet" do
      expect(build(:trip, status: :requested).can_transition_to?(:cancelled, actor_role: :customer)).to be true
    end

    it "refuses a jump from requested straight to completed, even for admin" do
      expect(build(:trip, status: :requested).can_transition_to?(:completed, actor_role: :admin)).to be false
    end
  end

  describe "the ride money model" do
    let(:trip) { create(:trip) }

    # This is the whole reason rides are the simpler half of Model A: on a food
    # order the courier advances the restaurant payout out of their own pocket.
    # On a ride they advance nothing.
    it "advances nothing to anybody" do
      expect(trip.courier_advance).to eq(0)
    end

    it "leaves the courier owing exactly our commission" do
      expect(trip.platform_cash_held).to eq(trip.commission)
    end

    it "reconciles: what the courier keeps plus our commission is the fare" do
      expect(trip.courier_earnings + trip.commission).to be_within(0.01).of(trip.fare)
    end
  end

  describe "#overdue?" do
    it "is false for a trip just requested" do
      expect(create(:trip)).not_to be_overdue
    end

    it "is true once nobody has accepted within the timeout" do
      expect(create(:trip, :overdue)).to be_overdue
    end

    it "is false for a completed trip, which has no timeout" do
      expect(create(:trip, :completed)).not_to be_overdue
    end
  end

  describe "scopes" do
    it ".live excludes completed, cancelled and failed" do
      live = create(:trip, :in_progress)
      create(:trip, :completed)
      create(:trip, :cancelled)
      create(:trip, :failed)

      expect(described_class.live).to contain_exactly(live)
    end

    it ".unsettled is every trip whose money has not reached us" do
      requested = create(:trip)
      collected = create(:trip, :completed)
      create(:trip, :completed, :settled)

      expect(described_class.unsettled).to contain_exactly(requested, collected)
    end
  end

  describe "sharing the dispatch machinery with Order" do
    it "takes offers through the same polymorphic table" do
      trip = create(:trip)
      order = create(:order)
      trip_offer = create(:offer, offerable: trip)
      order_offer = create(:offer, offerable: order)

      expect(trip.offers).to contain_exactly(trip_offer)
      expect(order.offers).to contain_exactly(order_offer)
      expect(Offer.count).to eq(2)
    end

    it "logs transitions through the same polymorphic table" do
      trip = create(:trip)
      courier = create(:user, :trip_courier)

      expect(trip.transition_to!(:accepted, actor: courier, actor_role: :courier)).to be true
      expect(trip.reload.status).to eq("accepted")
      expect(trip.accepted_at).to be_present
      expect(trip.transitions.last).to have_attributes(
        from_status: "requested", to_status: "accepted", actor_id: courier.id
      )
    end

    it "refuses an illegal transition without raising, and writes no log row" do
      trip = create(:trip)

      expect(trip.transition_to!(:completed, actor: nil, actor_role: :admin)).to be false
      expect(trip.reload.status).to eq("requested")
      expect(trip.transitions).to be_empty
    end
  end
end
