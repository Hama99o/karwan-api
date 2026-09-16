require "rails_helper"

RSpec.describe Pricing::RideQuote do
  def quote(pickup: [ 34.5400, 69.1750 ], dropoff: [ 34.5658, 69.2123 ], vehicle_type: nil)
    described_class.new(
      pickup_latitude: pickup[0], pickup_longitude: pickup[1],
      dropoff_latitude: dropoff[0], dropoff_longitude: dropoff[1],
      vehicle_type: vehicle_type
    ).call
  end

  # THE TARIFF IS A ROW, and this is the rate the un-classed quote reads.
  def any_vehicle_rate
    PricingRate.fetch(job_kind: "ride", audience: :customer)
  end

  describe "the simple distance-and-time formula" do
    # Derived from the actual distance rather than hardcoded: the first version
    # of this example asserted 14 minutes from an assumed 4.2km, and the real
    # pair is ~4.35km, so 15. Hardcoding a number computed by hand from a
    # rounded input is how a spec ends up asserting the author's arithmetic
    # instead of the code's.
    it "charges base, distance and time" do
      result = quote
      km = BigDecimal(result.distance_km.to_s)
      rate = any_vehicle_rate

      expected = rate.base + (rate.per_km * km) + (rate.per_minute * result.duration_minutes)

      expect(result.distance_km).to be_within(0.5).of(4.3)
      expect(result.duration_minutes).to eq(Geo::Distance.travel_minutes(result.distance_km))
      expect(result.amounts[:fare]).to eq(expected.round(2))
    end

    # ── THE EXAMPLE THAT SAYS WHERE THE TARIFF COMES FROM ───────────────────
    #
    # The one above cannot tell: the seeded any-vehicle row reproduces the old
    # `trip_*` settings exactly, so both sources agree and a fare read from
    # either would pass. `docs/TESTING.md`: make the sources disagree.
    #
    # So this one writes a rate NOTHING ELSE COULD HAVE PRODUCED — a 777 floor
    # is not a number any setting or default holds — and asserts the fare
    # follows the row.
    it "reads the tariff from the rate row, not from anywhere else" do
      PricingRate.seed_defaults!
      PricingRate.find_by!(job_kind: "ride", audience: :customer, vehicle_type: nil)
                 .update!(base: 0, per_km: 0, per_minute: 0, minimum: 777)

      expect(quote.amounts[:fare]).to eq(777)
    end

    # THE PASSENGER'S CHOICE IS THE PRICE. A car costs more than a motorbike
    # over the same route, which is the whole reason the class is chosen before
    # the quote rather than discovered after dispatch.
    it "charges a car more than a motorbike for the same route" do
      PricingRate.seed_defaults!

      motorbike = quote(vehicle_type: :motorbike).amounts[:fare]
      car = quote(vehicle_type: :car).amounts[:fare]

      expect(car).to be > motorbike
    end

    it "hits the figures Hamma9900 gave: a rider near 150 and a driver near 200 over 10km" do
      PricingRate.seed_defaults!
      rider = PricingRate.fetch(job_kind: "ride", audience: :customer, vehicle_type: :motorbike)
      driver = PricingRate.fetch(job_kind: "ride", audience: :customer, vehicle_type: :car)
      minutes = Geo::Distance.travel_minutes(10)

      expect(rider.amount_for(distance_km: 10, duration_minutes: minutes)).to be_within(15).of(150)
      expect(driver.amount_for(distance_km: 10, duration_minutes: minutes)).to be_within(15).of(200)
    end

    # The per-minute term is what stops a short crawl through Kabul traffic
    # being priced as if it were quick. Distance alone underpays the driver
    # sitting in it.
    it "charges more when the time term rises" do
      before = quote.amounts[:fare]
      PricingRate.seed_defaults!
      PricingRate.find_by!(job_kind: "ride", audience: :customer, vehicle_type: nil)
                 .update!(per_minute: 10)

      expect(quote.amounts[:fare]).to be > before
    end

    it "applies the minimum on a very short ride" do
      result = quote(dropoff: [ 34.5401, 69.1751 ])

      expect(result.amounts[:fare]).to eq(any_vehicle_rate.minimum)
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
