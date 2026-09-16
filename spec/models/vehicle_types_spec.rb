require "rails_helper"

# THE VEHICLE VOCABULARY, AND THE BOOT FAILURE THAT MOVED IT HERE.
#
# `CARRIES` and `SEATS` lived on `CourierProfile`, and `Trip`, `Order` and
# `PricingRate` read them from there — in their CLASS BODIES. That makes two
# models load-order dependent, and under eager loading `Trip` could be reached
# while `CourierProfile` was still part-way through its own body:
#
#   app/models/trip.rb:79: uninitialized constant CourierProfile::SEATS
#
# It passed `zeitwerk:check`, passed all 1,304 examples, and reproduced only in
# `RAILS_ENV=test bin/rails runner`. **Production eager-loads**, so it was a
# boot failure waiting for a load order nobody had hit yet — the worst kind,
# because the first person to hit it would be Hamma9900 on a deploy.
RSpec.describe VehicleTypes do
  describe "the vocabulary" do
    # The integers are stored on four tables. Append, never renumber —
    # renumbering turns every car in the database into a rishka.
    it "is the contract, and every table that stores it agrees" do
      expect(described_class::ALL).to eq(
        motorbike: 0, bicycle: 1, car: 2, on_foot: 3, rishka: 4, zarang: 5
      )
      expect(CourierProfile.vehicle_types).to eq(described_class::ALL.transform_keys(&:to_s))
      expect(Trip.vehicle_types).to eq(CourierProfile.vehicle_types)
      expect(PricingRate.vehicle_types).to eq(CourierProfile.vehicle_types)
      expect(Order.courier_vehicle_types).to eq(CourierProfile.vehicle_types)
    end

    # ── THE STRUCTURAL GUARD ─────────────────────────────────────────────────
    #
    # The fix is only durable if nobody reintroduces the reference. A class body
    # reaching into another MODEL is the defect; reading a plain module is not.
    it "is read from the module, never from another model" do
      %w[trip.rb order.rb pricing_rate.rb].each do |file|
        source = Rails.root.join("app/models", file).read

        expect(source).not_to match(/CourierProfile\.vehicle_types/), "#{file} reaches into a model"
        expect(source).not_to match(/CourierProfile::(SEATS|CARRIES|MAX_SEATS)/), "#{file} reaches into a model"
      end
    end

    # A module with no ActiveRecord in it cannot participate in a load cycle
    # with a model, which is the whole reason this is a module.
    #
    # COMMENTS ARE STRIPPED FIRST, and this example is why the rule is worth
    # stating twice: its first version failed because the module's own HEADER
    # names `CourierProfile`, `Trip`, `Order` and `PricingRate` while
    # explaining the boot failure that moved the vocabulary here. A gate that
    # fails on its own documentation trains people to delete the documentation
    # — the build is red, the comment is "just a comment", and the deadline is
    # real. Then the next person has the rule with no explanation and undoes
    # it. The mobile repo's separability gate hit the identical trap on the
    # same day; `docs/TESTING.md` carries the rule.
    it "depends on nothing that depends on it" do
      source = Rails.root.join("app/models/concerns/vehicle_types.rb").read
      code = source.gsub(%r{/\*.*?\*/}m, "").gsub(/^\s*#.*$/, "")

      expect(code).not_to match(/ApplicationRecord|CourierProfile|Trip\b|Order\b|PricingRate/)
    end
  end

  describe "what each vehicle carries" do
    it "does not read as a ladder from bicycle to car, because a zarang beats a car" do
      expect(described_class::CARRIES[:zarang]).to eq(:bulky)
      expect(described_class::CARRIES[:car]).to eq(:large)
      expect(SizeClasses.rank(described_class::CARRIES[:zarang]))
        .to be > SizeClasses.rank(described_class::CARRIES[:car])
    end

    # FAILS CLOSED. A vehicle added to the vocabulary with no capacity is one
    # nobody should be offered a bulky job on: a missing entry costs a dispatch,
    # failing open costs a courier a wasted journey and a customer a delivery.
    it "refuses an unknown vehicle everything, including the smallest job" do
      expect(described_class.carries?("hovercraft", :small)).to be false
      expect(described_class.carries?(nil, :small)).to be false
      expect(described_class.seats?("hovercraft", 1)).to be false
    end

    it "gives every vehicle in the vocabulary a capacity and a seat count" do
      # The three tables must not drift: a vehicle somebody can register as,
      # with no capacity, is a courier who can never be dispatched.
      expect(described_class::CARRIES.keys.sort).to eq(described_class::ALL.keys.sort)
      expect(described_class::SEATS.keys.sort).to eq(described_class::ALL.keys.sort)
    end
  end

  describe "how many it seats" do
    it "seats nobody on a bicycle or on foot" do
      expect(described_class.seats?("bicycle", 1)).to be false
      expect(described_class.seats?("on_foot", 1)).to be false
    end

    it "caps a booking at the largest vehicle on the platform" do
      expect(described_class::MAX_SEATS).to eq(described_class::SEATS.values.max)
      expect(build(:trip, passenger_count: described_class::MAX_SEATS)).to be_valid
      expect(build(:trip, passenger_count: described_class::MAX_SEATS + 1)).not_to be_valid
    end
  end
end
