require "rails_helper"

RSpec.describe Pricing::RideQuote do
  def quote(pickup: [ 34.5400, 69.1750 ], dropoff: [ 34.5658, 69.2123 ])
    described_class.new(
      pickup_latitude: pickup[0], pickup_longitude: pickup[1],
      dropoff_latitude: dropoff[0], dropoff_longitude: dropoff[1]
    ).call
  end

  describe "the simple distance-and-time formula" do
    # base 50 + 25/km + 2/min, at the default 18 km/h. Derived from the actual
    # distance rather than hardcoded: the first version of this example asserted
    # 14 minutes from an assumed 4.2km, and the real pair is ~4.35km, so 15.
    # Hardcoding a number computed by hand from a rounded input is how a spec
    # ends up asserting the author's arithmetic instead of the code's.
    it "charges base, distance and time" do
      result = quote
      km = BigDecimal(result.distance_km.to_s)

      expected = Setting.fetch("trip_base_fare") +
                 (Setting.fetch("trip_fare_per_km") * km) +
                 (Setting.fetch("trip_fare_per_minute") * result.duration_minutes)

      expect(result.distance_km).to be_within(0.5).of(4.3)
      expect(result.duration_minutes).to eq(Geo::Distance.travel_minutes(result.distance_km))
      expect(result.amounts[:fare]).to eq(expected.round(2))
    end

    # The per-minute term is what stops a short crawl through Kabul traffic
    # being priced as if it were quick. Distance alone underpays the driver
    # sitting in it.
    it "charges more when the time term rises" do
      before = quote.amounts[:fare]
      Setting.seed_defaults!
      Setting.find_by!(key: "trip_fare_per_minute").update!(value: "10.0")

      expect(quote.amounts[:fare]).to be > before
    end

    it "applies the minimum on a very short ride" do
      result = quote(dropoff: [ 34.5401, 69.1751 ])

      expect(result.amounts[:fare]).to eq(Setting.fetch("trip_minimum_fare"))
    end

    it "charges more for a longer ride" do
      near = quote(dropoff: [ 34.5420, 69.1770 ]).amounts[:fare]
      far = quote(dropoff: [ 34.6500, 69.3500 ]).amounts[:fare]

      expect(far).to be > near
    end
  end

  describe "the ride money model" do
    it "splits the fare into our commission and what the courier keeps" do
      amounts = quote.amounts

      expect(amounts[:courier_earnings] + amounts[:commission]).to eq(amounts[:fare])
    end

    # Derived by subtraction rather than computed independently, so the two
    # halves always reconstitute the fare exactly and
    # Trip#fare_splits_correctly cannot fail on a rounding artefact.
    it "reconstitutes the fare exactly at every distance, with no rounding drift" do
      20.times do |i|
        result = quote(dropoff: [ 34.54 + (i * 0.004), 69.175 + (i * 0.006) ])
        amounts = result.amounts

        expect(amounts[:courier_earnings] + amounts[:commission]).to eq(amounts[:fare]),
          "drift at #{result.distance_km}km"
      end
    end

    it "produces amounts a Trip accepts, including the split validation" do
      passenger = create(:user, :customer)
      result = quote

      trip = Trip.new(
        result.to_attributes.merge(
          passenger: passenger,
          pickup_latitude: 34.5400, pickup_longitude: 69.1750,
          dropoff_latitude: 34.5658, dropoff_longitude: 69.2123,
          passenger_phone: passenger.phone, payment_method: :cash,
          distance_km: result.distance_km, duration_minutes: result.duration_minutes,
          requested_at: Time.current
        )
      )

      expect(trip).to be_valid, trip.errors.full_messages.join("; ")
    end

    it "advances nothing, which is what makes a ride the simpler half" do
      passenger = create(:user, :customer)
      result = quote
      trip = Trip.new(result.to_attributes.merge(
                        passenger: passenger,
                        pickup_latitude: 34.54, pickup_longitude: 69.175,
                        dropoff_latitude: 34.5658, dropoff_longitude: 69.2123,
                        passenger_phone: passenger.phone
                      ))

      expect(trip.courier_advance).to eq(0)
      expect(trip.wallet_requirement).to eq(0)
    end
  end

  describe "failure" do
    it "refuses to price without both pins" do
      expect { quote(dropoff: [ nil, nil ]) }.to raise_error(described_class::Error, /both pins/)
    end
  end
end
