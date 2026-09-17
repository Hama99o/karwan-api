require "rails_helper"

# EVERY AMOUNT IS FROZEN WHERE IT WAS AGREED, and this file is the one place
# that proves it for all of them together.
#
# `docs/TESTING.md`: a test that a value is STORED correctly is not a test that
# it is FROZEN. Each example here changes the configuration UNDERNEATH a placed
# job and asserts the job does not move — which is the only way to tell a
# snapshot from a live read, because in every ordinary fixture the two agree.
#
# There are now three freeze points and they are deliberately different:
#
#   at QUOTE       — everything the customer was told. Never moves.
#   at ASSIGNMENT  — the courier's fee, because the vehicle is unknown until
#                    somebody accepts.
#   never          — the dispatch WARNING about vehicle availability, which is
#                    recomputed so a zarang coming on shift makes it disappear.
RSpec.describe "frozen amounts" do
  let(:merchant) { create(:merchant, latitude: 34.5553, longitude: 69.2075) }
  let(:category) { create(:catalog_category, merchant: merchant) }
  let!(:kabab) { create(:catalog_item, catalog_category: category, merchant: merchant, price: 400) }

  def place(tier: :normal)
    Orders::PlaceService.new(
      customer: create(:user, :customer), merchant: merchant,
      lines: [ { catalog_item_id: kabab.id, quantity: 1 } ],
      delivery_latitude: 34.5600, delivery_longitude: 69.2100,
      service_tier: tier
    ).call
  end

  def stub_osrm(distance_m:)
    stub_request(:get, %r{http://karwan_osrm:5000}).to_return(
      body: { code: "Ok",
              routes: [ { distance: distance_m, duration: 400.0,
                          geometry: { type: "LineString", coordinates: [ [ 69.17, 34.54 ] ] } } ],
              waypoints: [ { distance: 10.0 }, { distance: 10.0 } ] }.to_json
    )
  end

  before { Setting.seed_defaults! }

  # ── THE ROUTING SWITCH ─────────────────────────────────────────────────────
  #
  # Hamma9900 has decided to turn OSRM on. Measured on this box against four
  # Kabul pairs: road distance runs 1.24–1.47× the straight line, which moves
  # the DELIVERY FEE by +15% to +20% on ordinary runs and by nothing at all on
  # a short hop, where the minimum fee absorbs it. (The earlier +29% estimate
  # was a distance ratio, not a fee change — the fixed base dilutes it.)
  #
  # The switch is a `Setting`, so it can be flipped while orders are in flight.
  # These examples are what makes that safe.
  describe "when the distance source is switched mid-flight" do
    it "does not re-price an order that was already placed" do
      order = place
      frozen = order.slice(:distance_km, :delivery_fee, :customer_total, :distance_source)

      stub_osrm(distance_m: 9_000.0)
      Setting.find_by!(key: "routing_distance_source").update!(value: "osrm")

      expect(order.reload.slice(:distance_km, :delivery_fee, :customer_total, :distance_source))
        .to eq(frozen)
    end

    # The row RECORDS which method produced its distance, which is the only way
    # to answer "why was that one cheaper" after the switch.
    it "records the source that priced it, so a fare can be explained afterwards" do
      straight = place

      stub_osrm(distance_m: 9_000.0)
      Setting.find_by!(key: "routing_distance_source").update!(value: "osrm")
      routed = place

      expect(straight.distance_source).to eq("straight_line")
      expect(routed.distance_source).to eq("osrm")
      expect(routed.distance_km).to eq(9.0)
    end

    # A LONGER ROAD COSTS MORE, which is the whole reason to adopt it — and the
    # customer sees that number before committing, never after.
    it "prices a new order on the road distance once it is on" do
      straight = place

      stub_osrm(distance_m: 9_000.0)
      Setting.find_by!(key: "routing_distance_source").update!(value: "osrm")

      expect(place.delivery_fee).to be > straight.delivery_fee
    end

    # The duration is OURS, from `eta_average_speed_kmh`, never OSRM's — whose
    # `car.lua` free-flow estimates imply 43-69 km/h across Kabul because
    # maxspeed tags are sparse. Verified against the live container: 5.53 km
    # came back as 7.7 minutes from OSRM and 19 from us.
    it "keeps taking the duration from the calibratable setting" do
      stub_osrm(distance_m: 9_000.0)
      Setting.find_by!(key: "routing_distance_source").update!(value: "osrm")

      order = place

      expect(order.duration_minutes).to be >= Geo::Distance.travel_minutes(9.0)
    end
  end

  # ── THE DISTANCE SHOWN AT BROWSE TIME IS NOT THE DISTANCE THE FARE FROZE ──
  #
  # Both go through OSRM now, so they will usually agree — and "usually agree"
  # is exactly the condition under which a test cannot tell which one was used.
  # So the list is made to answer something the quote cannot: the order must
  # carry the QUOTE's distance, measured merchant→customer, not the browse
  # distance, measured customer→merchant over a page of cards.
  describe "the distance the order freezes" do
    it "is the quote's own measurement, not the one the list showed" do
      Setting.find_by!(key: "routing_distance_source").update!(value: "osrm")
      # The list says 9.1 km to every merchant; the quote says 4 km for this
      # route. A number from the list appearing on the order would be visible.
      stub_request(:get, %r{/table/v1/}).to_return do |request|
        asked = request.uri.path.split("/").last.split(";").size - 1
        { body: { code: "Ok", distances: [ [ 0.0, *Array.new(asked, 9_100.0) ] ] }.to_json }
      end
      stub_osrm(distance_m: 4_000.0)

      # Browse first, so the list's figure exists and could be picked up.
      Routing::DistanceTable.new(
        origin_lat: 34.5600, origin_lng: 69.2100,
        destinations: [ { key: merchant.id, latitude: merchant.latitude, longitude: merchant.longitude } ]
      ).call

      order = place

      expect(order.distance_km).to eq(4.0)
      expect(order.distance_source).to eq("osrm")
    end
  end

  describe "when the delivery tariff changes" do
    it "does not move a placed order's fee" do
      order = place
      frozen = order.delivery_fee

      Setting.find_by!(key: "delivery_base_fee").update!(value: "500")

      expect(order.reload.delivery_fee).to eq(frozen)
    end
  end

  # THE ONE MOST LIKELY TO BE ASKED ABOUT, because it is the only setting here
  # that is MEANT to move within a day: it goes up in a storm and comes back
  # down the same evening. "Why was my delivery 260 last Tuesday" is a question
  # about a number that exists nowhere by Wednesday unless the row holds it.
  describe "when the shortage multiplier is turned on and off" do
    def storm(multiplier)
      Setting.find_by!(key: "shortage_multiplier").update!(value: multiplier)
      Setting.find_by!(key: "shortage_multiplier_enabled").update!(value: "true")
    end

    it "does not move an order placed during the storm once it passes" do
      storm("1.6")
      order = place
      frozen = order.delivery_fee
      courier_frozen = order.courier_fee

      Setting.find_by!(key: "shortage_multiplier_enabled").update!(value: "false")

      expect(order.reload.delivery_fee).to eq(frozen)
      expect(order.courier_fee).to eq(courier_frozen)
    end

    it "keeps the multiplier itself on the row, so the fee can be explained" do
      storm("1.6")
      order = place

      Setting.find_by!(key: "shortage_multiplier_enabled").update!(value: "false")

      expect(order.reload.shortage_multiplier).to eq(BigDecimal("1.6"))
    end

    # The audit half: what the console ASKED for, beside what was applied, so a
    # capped fare is distinguishable from an uncapped one long after the
    # setting has been put back.
    it "records a capped storm as the two different numbers it was" do
      Setting.find_by!(key: "max_total_multiplier").update!(value: "2.0")
      storm("9")
      order = place

      expect(order.shortage_multiplier).to eq(BigDecimal("2.0"))
      expect(order.shortage_multiplier_requested).to eq(BigDecimal("9"))
    end

    it "leaves an order placed before the storm alone" do
      order = place
      frozen = order.delivery_fee

      storm("1.6")

      expect(order.reload.delivery_fee).to eq(frozen)
      expect(order.shortage_multiplier).to eq(1)
    end
  end

  describe "when a ride's rate row changes" do
    def ride
      quote = Pricing::RideQuote.new(
        pickup_latitude: 34.54, pickup_longitude: 69.175,
        dropoff_latitude: 34.5658, dropoff_longitude: 69.2123,
        vehicle_type: :car
      ).call
      passenger = create(:user, :customer)
      Trip.create!(quote.to_attributes.merge(
                     passenger: passenger, passenger_phone: passenger.phone,
                     pickup_latitude: 34.54, pickup_longitude: 69.175,
                     dropoff_latitude: 34.5658, dropoff_longitude: 69.2123,
                     vehicle_type: :car, payment_method: :cash, requested_at: Time.current
                   ))
    end

    it "does not move a booked trip's fare" do
      trip = ride
      frozen = trip.fare

      PricingRate.seed_defaults!
      PricingRate.find_by!(job_kind: "ride", audience: :customer, vehicle_type: :car)
                 .update!(base: 5_000)

      expect(trip.reload.fare).to eq(frozen)
    end

    it "keeps the split adding up, so the row stays valid" do
      trip = ride

      expect(trip.fare).to eq(trip.commission + trip.courier_earnings)
    end
  end
end
