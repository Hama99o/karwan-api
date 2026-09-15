require "rails_helper"

RSpec.describe Geo::Distance do
  describe ".km" do
    # Checked against a known real-world pair rather than against itself:
    # Shar-e-Naw to Kabul International Airport is about 4km as the crow flies.
    it "computes a known Kabul distance" do
      km = described_class.km(from_lat: 34.5400, from_lng: 69.1750,
                              to_lat: 34.5658, to_lng: 69.2123)

      expect(km).to be_within(0.5).of(4.2)
    end

    it "is zero for the same point" do
      expect(described_class.km(from_lat: 34.55, from_lng: 69.20,
                                to_lat: 34.55, to_lng: 69.20)).to eq(0.0)
    end

    it "is symmetric" do
      a = described_class.km(from_lat: 34.54, from_lng: 69.17, to_lat: 34.57, to_lng: 69.21)
      b = described_class.km(from_lat: 34.57, from_lng: 69.21, to_lat: 34.54, to_lng: 69.17)

      expect(a).to eq(b)
    end

    # A missing pin must not price as "zero kilometres away", which would
    # silently charge the minimum fee for a job of unknown length.
    it "returns nil for a missing coordinate, not zero" do
      expect(described_class.km(from_lat: nil, from_lng: 69.17, to_lat: 34.57, to_lng: 69.21)).to be_nil
      expect(described_class.km(from_lat: 34.54, from_lng: 69.17, to_lat: 34.57, to_lng: nil)).to be_nil
    end

    it "handles antipodal points without NaN from a floating-point overshoot" do
      km = described_class.km(from_lat: 0, from_lng: 0, to_lat: 0, to_lng: 180)

      expect(km).to be_finite
      expect(km).to be_within(1.0).of(20_015)
    end

    it "works across the equator and the meridian" do
      expect(described_class.km(from_lat: -1.0, from_lng: -1.0, to_lat: 1.0, to_lng: 1.0)).to be > 0
    end

    it "accepts BigDecimal coordinates, which is what the database returns" do
      km = described_class.km(from_lat: BigDecimal("34.54"), from_lng: BigDecimal("69.175"),
                              to_lat: BigDecimal("34.5658"), to_lng: BigDecimal("69.2123"))

      expect(km).to be_within(0.5).of(4.2)
    end
  end

  describe ".travel_minutes" do
    it "uses the configured average speed" do
      # 18 km/h default: 4.2km is 14 minutes.
      expect(described_class.travel_minutes(4.2)).to eq(14)
    end

    # Ceiled, because telling someone 14 when it is 14.2 reads as late.
    it "rounds up, never down" do
      expect(described_class.travel_minutes(4.25)).to eq(15)
    end

    it "honours an explicit speed over the setting" do
      expect(described_class.travel_minutes(10, speed_kmh: 60)).to eq(10)
    end

    it "returns nil for an unknown distance" do
      expect(described_class.travel_minutes(nil)).to be_nil
    end

    # A misconfigured speed of zero would divide by zero. Returning nil makes
    # the caller deal with "unknown" rather than crashing an order.
    it "returns nil rather than dividing by a zero speed" do
      expect(described_class.travel_minutes(5, speed_kmh: 0)).to be_nil
    end
  end
end
