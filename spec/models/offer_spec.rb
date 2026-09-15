require "rails_helper"

RSpec.describe Offer, type: :model do
  describe "validations" do
    it { is_expected.to belong_to(:offerable) }
    it { is_expected.to belong_to(:courier) }
    it { is_expected.to validate_presence_of(:offered_at) }
    it { is_expected.to validate_presence_of(:expires_at) }

    # The courier gets ONE offer at a time, never a list — a list needs reading
    # and comparing, and invites cherry-picking that starves the far jobs. The
    # sequence is what makes "the third courier we tried" answerable.
    it "requires a unique sequence within one job" do
      order = create(:order)
      create(:offer, offerable: order, sequence: 1)
      duplicate = build(:offer, offerable: order, sequence: 1)

      expect(duplicate).not_to be_valid
    end

    # Polymorphic, so the uniqueness scope must include the TYPE. Without it,
    # order 7 and trip 7 would collide and the second offer would be rejected
    # for no reason a person could understand.
    it "allows the same sequence on a different job, including a different kind" do
      order = create(:order)
      trip = create(:trip)
      create(:offer, offerable: order, sequence: 1)

      expect(build(:offer, offerable: trip, sequence: 1)).to be_valid
      expect(build(:offer, offerable: create(:order), sequence: 1)).to be_valid
    end

    it "rejects a zero or negative sequence" do
      expect(build(:offer, sequence: 0)).not_to be_valid
    end
  end

  describe "#expired?" do
    # Every offer has a deadline. An offer with no timeout is how a job sits
    # unassigned while a courier who went home never declines it.
    it "is false while the clock is running" do
      expect(create(:offer)).not_to be_expired
    end

    it "is true once the deadline passes" do
      expect(create(:offer, :expired)).to be_expired
    end

    # An answered offer is not expired, it is answered. Treating it as expired
    # would make a timeout job re-offer a job somebody already took.
    it "is false for an offer that was already accepted, even long ago" do
      offer = create(:offer, :accepted, expires_at: 1.hour.ago)

      expect(offer).not_to be_expired
    end

    it "is false for an offer that was declined" do
      expect(create(:offer, :declined, expires_at: 1.hour.ago)).not_to be_expired
    end
  end

  describe "#respond!" do
    it "records the answer and when it came" do
      offer = create(:offer)

      offer.respond!(:accepted)

      expect(offer.reload.status).to eq("accepted")
      expect(offer.responded_at).to be_within(5.seconds).of(Time.current)
    end

    it "records a decline, which needs no reason" do
      offer = create(:offer)

      offer.respond!(:declined)

      expect(offer.reload.status).to eq("declined")
    end
  end

  describe "scopes" do
    describe ".pending" do
      it "is only live offers whose clock is still running" do
        live = create(:offer)
        create(:offer, :expired)
        create(:offer, :accepted)
        create(:offer, :declined)

        expect(described_class.pending).to contain_exactly(live)
      end
    end

    describe ".expired" do
      # This is what a timeout job consumes: offers still marked `offered`
      # whose deadline has passed. An accepted offer past its deadline must
      # NOT appear, or the job would re-offer work already taken.
      it "is only unanswered offers past their deadline" do
        stale = create(:offer, :expired)
        create(:offer)
        create(:offer, :accepted, expires_at: 1.hour.ago)

        expect(described_class.expired).to contain_exactly(stale)
      end
    end

    describe ".chronological" do
      it "orders by the sequence they were offered in" do
        order = create(:order)
        third = create(:offer, offerable: order, sequence: 3)
        first = create(:offer, offerable: order, sequence: 1)
        second = create(:offer, offerable: order, sequence: 2)

        expect(order.offers.chronological).to eq([ first, second, third ])
      end
    end
  end

  describe "serving both demand types through one table" do
    it "attaches to an order and to a trip" do
      order = create(:order)
      trip = create(:trip)

      order_offer = create(:offer, offerable: order)
      trip_offer = create(:offer, offerable: trip)

      expect(order_offer.offerable).to eq(order)
      expect(trip_offer.offerable).to eq(trip)
    end

    it "is destroyed with its job, leaving no orphan offers" do
      order = create(:order)
      create(:offer, offerable: order)

      expect { order.destroy }.to change(described_class, :count).by(-1)
    end
  end

  describe "statuses" do
    it "distinguishes a decline from a timeout from being superseded" do
      expect(described_class.statuses.keys)
        .to eq(%w[offered accepted declined timed_out superseded])
    end
  end
end
