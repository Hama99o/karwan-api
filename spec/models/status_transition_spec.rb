require "rails_helper"

RSpec.describe StatusTransition, type: :model do
  describe "validations" do
    it { is_expected.to belong_to(:subject) }
    it { is_expected.to belong_to(:actor).optional }
    it { is_expected.to validate_presence_of(:to_status) }

    # Statuses are STRINGS, not an integer enum, because this table is
    # polymorphic over Order and Trip and the two have different vocabularies —
    # integer 3 would mean `ready` for an order and something unrelated for a
    # trip. Integrity comes from checking against the subject's own STATUSES
    # instead, which also means a third demand type needs no change here.
    it "accepts a status the subject actually has" do
      expect(build(:status_transition, subject: create(:order),
                                       from_status: "placed", to_status: "accepted")).to be_valid
    end

    it "rejects a status the subject does not have" do
      transition = build(:status_transition, subject: create(:order), to_status: "teleported")

      expect(transition).not_to be_valid
      expect(transition.errors[:to_status].join).to include("Order")
    end

    # The real value of validating against the subject: a trip status on an
    # order is caught, where an integer enum would have accepted it silently
    # because the number is in range.
    it "rejects a trip status on an order" do
      transition = build(:status_transition, subject: create(:order), to_status: "in_progress")

      expect(transition).not_to be_valid
    end

    it "accepts a trip status on a trip" do
      expect(build(:status_transition, subject: create(:trip),
                                       from_status: "requested", to_status: "accepted")).to be_valid
    end

    it "allows a blank from_status, for the first transition of a job's life" do
      expect(build(:status_transition, subject: create(:order),
                                       from_status: nil, to_status: "accepted")).to be_valid
    end
  end

  describe "#system?" do
    # The difference between "the merchant rejected it" and "the merchant never
    # answered". Support needs to tell those apart, and only the actor does it.
    it "is false when a person made the move" do
      expect(create(:status_transition)).not_to be_system
    end

    it "is true when a timeout fired" do
      expect(create(:status_transition, :system)).to be_system
    end
  end

  describe ".chronological" do
    it "reads the history in the order it happened" do
      order = create(:order)
      create(:status_transition, subject: order, to_status: "accepted", created_at: 3.minutes.ago)
      create(:status_transition, subject: order, from_status: "accepted", to_status: "preparing", created_at: 2.minutes.ago)
      create(:status_transition, subject: order, from_status: "preparing", to_status: "ready", created_at: 1.minute.ago)

      expect(order.transitions.chronological.map(&:to_status)).to eq(%w[accepted preparing ready])
    end
  end

  describe "as an append-only log" do
    # One-way door #3 in CLAUDE.md: "how long do orders sit in preparing" is
    # the metric that runs a delivery business and cannot be backfilled.
    it "has no updated_at, because a ledger row that can be edited is not a ledger" do
      expect(described_class.column_names).not_to include("updated_at")
      expect(described_class.column_names).to include("created_at")
    end

    it "records the actor's role alongside the actor" do
      merchant_owner = create(:user, :merchant_owner)
      transition = create(:status_transition, actor: merchant_owner, actor_role: :merchant_owner)

      expect(transition.actor_role).to eq("merchant_owner")
      expect(transition).to be_by_merchant_owner
    end
  end

  describe "written by Dispatchable#transition_to!" do
    it "captures the from and to of a real move on an order" do
      order = create(:order)
      owner = create(:user, :merchant_owner)

      order.transition_to!(:accepted, actor: owner, actor_role: :merchant_owner)

      expect(order.transitions.last).to have_attributes(
        from_status: "placed", to_status: "accepted",
        actor_id: owner.id, actor_role: "merchant_owner"
      )
    end

    it "captures a move on a trip through the same table" do
      trip = create(:trip)
      courier = create(:user, :ride_courier)

      trip.transition_to!(:accepted, actor: courier, actor_role: :courier)

      expect(trip.transitions.last).to have_attributes(
        from_status: "requested", to_status: "accepted", actor_role: "courier"
      )
      expect(described_class.where(subject_type: "Trip").count).to eq(1)
    end
  end
end
