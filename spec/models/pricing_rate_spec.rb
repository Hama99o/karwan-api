require "rails_helper"

# RATES THAT VARY BY VEHICLE, which a key-value `Setting` cannot hold.
#
# The rule these examples defend: **`Setting` holds scalars, `pricing_rates`
# holds anything that varies by vehicle.** Two mechanisms for one fare would
# mean code deciding which to trust.
RSpec.describe PricingRate, type: :model do
  describe "the vehicle enum" do
    # THE MISMATCH THAT WOULD HAVE BEEN SILENT. I first wrote this enum as
    # `CARRIES.keys.each_with_index`, which looks equivalent and is not:
    # `CARRIES` is ordered by capacity and the enum by when each vehicle was
    # added, so every rate would have been stored against the WRONG vehicle —
    # a car's fare charged for a rishka. Derive the mapping, never restate it.
    it "uses exactly the same integers as a courier's vehicle" do
      expect(described_class.vehicle_types).to eq(CourierProfile.vehicle_types)
    end
  end

  describe ".fetch" do
    it "prefers the class's own row" do
      described_class.seed_defaults!
      described_class.find_by!(job_kind: "ride", audience: :customer, vehicle_type: :car)
                     .update!(base: 999)

      rate = described_class.fetch(job_kind: "ride", audience: :customer, vehicle_type: :car)
      expect(rate.base).to eq(999)
    end

    it "falls back to the any-vehicle row" do
      described_class.seed_defaults!
      described_class.where(job_kind: "ride", audience: :customer).where.not(vehicle_type: nil).delete_all

      rate = described_class.fetch(job_kind: "ride", audience: :customer, vehicle_type: :car)
      expect(rate.vehicle_type).to be_nil
    end

    # Mirrors `Setting.fetch`: a rate nobody has seeded must not become a zero
    # fare, and a spec must not have to seed a table to price a ride.
    it "falls back to the declared default when nothing is seeded" do
      expect(described_class.count).to eq(0)

      rate = described_class.fetch(job_kind: "ride", audience: :customer, vehicle_type: :car)
      expect(rate).not_to be_persisted
      expect(rate.base).to eq(40)
    end

    it "does not write a row while reading one" do
      expect { described_class.fetch(job_kind: "ride", audience: :customer) }
        .not_to change(described_class, :count)
    end

    # A combination nobody declared is a typo, not a rate — the same reasoning
    # `Setting.fetch` raises on an unknown key rather than returning nil.
    it "raises for a combination nobody declared" do
      expect { described_class.fetch(job_kind: "ride", audience: :courier, vehicle_type: :car) }
        .to raise_error(KeyError, /add it to PricingRate::DEFAULTS/)
    end
  end

  describe "#amount_for" do
    let(:rate) { described_class.new(job_kind: "ride", audience: :customer, base: 30, per_km: 8, per_minute: 1.2, minimum: 60) }

    it "charges base plus distance plus time" do
      expect(rate.amount_for(distance_km: 10, duration_minutes: 33)).to eq(149.60)
    end

    it "applies the floor, which is what makes a very short job worth taking" do
      expect(rate.amount_for(distance_km: 0.2, duration_minutes: 1)).to eq(60)
    end

    # A delivery prices on distance alone, so one formula serves both demand
    # types rather than two nearly-identical ones.
    it "treats a missing duration as zero rather than raising" do
      expect(rate.amount_for(distance_km: 10)).to eq(110)
    end
  end

  describe "the seeded defaults" do
    before { described_class.seed_defaults! }

    it "hits the two figures Hamma9900 gave, over 10km" do
      minutes = Geo::Distance.travel_minutes(10)
      rider = described_class.fetch(job_kind: "ride", audience: :customer, vehicle_type: :motorbike)
      driver = described_class.fetch(job_kind: "ride", audience: :customer, vehicle_type: :car)

      expect(rider.amount_for(distance_km: 10, duration_minutes: minutes)).to be_within(15).of(150)
      expect(driver.amount_for(distance_km: 10, duration_minutes: minutes)).to be_within(15).of(200)
    end

    # INTRODUCING THIS TABLE MOVED NO MONEY. The delivery courier rows
    # reproduce the customer-facing delivery tariff exactly, so v0's "the
    # courier keeps the whole delivery fee" still holds — the per-vehicle
    # dimension now EXISTS and is a number he types when he wants it.
    it "pays a delivery courier exactly today's delivery fee, on every vehicle" do
      km = 3.5
      expected = Setting.fetch("delivery_base_fee") + (Setting.fetch("delivery_fee_per_km") * km)

      CourierProfile.vehicle_types.each_key do |vehicle|
        rate = described_class.fetch(job_kind: "delivery", audience: :courier, vehicle_type: vehicle)
        expect(rate.amount_for(distance_km: km)).to eq(expected.round(2)), "#{vehicle} differs"
      end
    end

    it "offers no ride on foot or by bicycle, because nobody hails a pedestrian" do
      selectable = described_class.for_job("ride").selectable.map(&:vehicle_type)

      expect(selectable).to include("car"), "no selectable ride rates — the check below is vacuous"
      expect(selectable).not_to include("on_foot", "bicycle")
      expect(selectable).to include("motorbike", "car")
    end

    # Re-seeding runs on every deploy. Overwriting a tuned number would
    # silently reprice every ride, which is the bug `Setting.seed_defaults!`
    # was already careful about.
    it "never overwrites a number Hamma9900 has typed" do
      row = described_class.find_by!(job_kind: "ride", audience: :customer, vehicle_type: :car)
      row.update!(per_km: 99)

      described_class.seed_defaults!

      expect(row.reload.per_km).to eq(99)
    end
  end

  describe "uniqueness" do
    it "refuses a second rate for the same audience, demand type and vehicle" do
      described_class.create!(job_kind: "ride", audience: :customer, vehicle_type: :car, base: 10)
      duplicate = described_class.new(job_kind: "ride", audience: :customer, vehicle_type: :car, base: 20)

      expect(duplicate).not_to be_valid
    end

    it "allows the same vehicle for a different audience" do
      described_class.create!(job_kind: "ride", audience: :customer, vehicle_type: :car, base: 10)
      other = described_class.new(job_kind: "delivery", audience: :courier, vehicle_type: :car, base: 20)

      expect(other).to be_valid
    end
  end
end
