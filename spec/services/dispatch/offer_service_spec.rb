require "rails_helper"

RSpec.describe Dispatch::OfferService do
  let(:merchant) { create(:merchant, latitude: 34.5553, longitude: 69.2075) }
  let(:order) do
    create(:order, merchant: merchant, items_total: 400, delivery_fee: 100,
                   customer_total: 500, commission: 50, merchant_payout: 350)
  end

  def courier_at(lat, lng, kinds: %w[delivery], balance: 1_000)
    user = create(:user, :courier)
    user.courier_profile.update!(is_available: true, accepted_job_kinds: kinds,
                                 last_latitude: lat, last_longitude: lng,
                                 location_updated_at: Time.current)
    user.courier_wallet.update!(balance: balance, credit_line: 500)
    user
  end

  describe "#call" do
    it "offers to an eligible courier with a deadline" do
      courier = courier_at(34.5553, 69.2075)

      offer = described_class.new(order).call

      expect(offer).to be_persisted
      expect(offer.courier).to eq(courier)
      expect(offer.status).to eq("offered")
      expect(offer.sequence).to eq(1)
      expect(offer.expires_at).to be_within(2.seconds)
        .of(Setting.fetch("dispatch_offer_ttl_sec").seconds.from_now)
    end

    # Nearest first. Not an optimisation — it is the difference between food
    # arriving warm and not.
    it "picks the nearest courier" do
      far = courier_at(34.6500, 69.3500)
      near = courier_at(34.5560, 69.2080)

      expect(described_class.new(order).call.courier).to eq(near)
      expect(far.reload.courier_orders).to be_empty
    end

    # Two live offers for one job is how two couriers both turn up at the
    # merchant and one has wasted a trip.
    it "will not create a second live offer for the same job" do
      courier_at(34.5553, 69.2075)
      courier_at(34.5560, 69.2080)

      described_class.new(order).call

      expect(described_class.new(order).call).to be_nil
      expect(order.offers.count).to eq(1)
    end

    it "offers to the next courier once the previous one declined" do
      first = courier_at(34.5553, 69.2075)
      second = courier_at(34.5600, 69.2100)

      described_class.new(order).call.respond!(:declined)
      offer = described_class.new(order).call

      expect(offer.courier).to eq(second)
      expect(offer.sequence).to eq(2)
      expect(offer.courier).not_to eq(first)
    end

    it "never asks the same courier twice" do
      only = courier_at(34.5553, 69.2075)

      described_class.new(order).call.respond!(:declined)

      expect(described_class.new(order).call).to be_nil
      expect(order.offers.pluck(:courier_id)).to eq([ only.id ])
    end

    # Nil is not a failure — it is the signal that a human is needed, which the
    # brief says to build first.
    it "returns nil when nobody is eligible" do
      expect(described_class.new(order).call).to be_nil
      expect(described_class.new(order).blocked_reason).to eq(:no_eligible_courier)
    end

    it "stops after the configured number of tries" do
      Setting.seed_defaults!
      Setting.find_by!(key: "dispatch_max_offers").update!(value: "2")
      3.times { |i| courier_at(34.5553 + (i * 0.001), 69.2075) }

      2.times { described_class.new(order).call.respond!(:declined) }

      expect(described_class.new(order).call).to be_nil
      expect(described_class.new(order).blocked_reason).to eq(:offers_exhausted)
    end

    it "does not offer a terminal job" do
      courier_at(34.5553, 69.2075)
      delivered = create(:order, :delivered, merchant: merchant)

      expect(described_class.new(delivered).call).to be_nil
      expect(described_class.new(delivered).blocked_reason).to eq(:terminal)
    end

    it "skips a courier whose wallet cannot fund the advance" do
      broke = courier_at(34.5553, 69.2075, balance: -400)
      funded = courier_at(34.5600, 69.2100, balance: 1_000)

      expect(described_class.new(order).call.courier).to eq(funded)
      expect(broke.reload.courier_orders).to be_empty
    end

    it "skips a courier whose position is too stale to dispatch on" do
      stale = courier_at(34.5553, 69.2075)
      stale.courier_profile.update!(location_updated_at: 1.hour.ago)
      fresh = courier_at(34.5700, 69.2200)

      expect(described_class.new(order).call.courier).to eq(fresh)
    end

    it "returns nil when the job has no pickup location to measure from" do
      courier_at(34.5553, 69.2075)
      merchant.update_columns(latitude: nil, longitude: nil)

      expect(described_class.new(order.reload).call).to be_nil
    end
  end

  describe "rides use the same dispatcher" do
    let(:ride) { create(:trip, fare: 160, commission: 20, courier_earnings: 140) }

    it "offers a ride to a courier who accepts rides" do
      courier = courier_at(34.5400, 69.1750, kinds: %w[ride])

      offer = described_class.new(ride).call

      expect(offer.courier).to eq(courier)
      expect(offer.offerable).to eq(ride)
    end

    it "does not offer a ride to a delivery-only courier" do
      courier_at(34.5400, 69.1750, kinds: %w[delivery])

      expect(described_class.new(ride).call).to be_nil
    end

    # The asymmetry, end to end through the dispatcher: the same wallet that is
    # too thin for a delivery is fine for a ride.
    it "offers a ride to a courier too short for a delivery" do
      courier = courier_at(34.5400, 69.1750, kinds: %w[delivery ride], balance: -400)

      expect(described_class.new(order).call).to be_nil
      expect(described_class.new(ride).call.courier).to eq(courier)
    end
  end
end
