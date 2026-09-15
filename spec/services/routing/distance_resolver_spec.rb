require "rails_helper"

RSpec.describe Routing::DistanceResolver do
  let(:from) { { lat: 34.5400, lng: 69.1750 } }
  let(:to) { { lat: 34.5658, lng: 69.2123 } }
  let(:base) { "http://karwan_osrm:5000" }

  def resolve
    described_class.new(from_lat: from[:lat], from_lng: from[:lng],
                        to_lat: to[:lat], to_lng: to[:lng]).call
  end

  def enable_osrm!
    Setting.seed_defaults!
    Setting.find_by!(key: "routing_distance_source").update!(value: "osrm")
  end

  def stub_osrm(distance_m: 5698.8, duration_s: 394.7)
    stub_request(:get, %r{#{Regexp.escape(base)}}).to_return(
      body: {
        code: "Ok",
        routes: [ { distance: distance_m, duration: duration_s,
                    geometry: { type: "LineString", coordinates: [ [ 69.17, 34.54 ] ] } } ],
        waypoints: [ { distance: 30.0 }, { distance: 40.0 } ]
      }.to_json
    )
  end

  describe "the default, which is straight-line" do
    # Defaults to OFF on purpose. The measurement is unambiguous — over eight
    # real Kabul routes the road/straight ratio runs 1.14 to 2.82 — but
    # switching raises fares about 29%, and that is Hamma9900's decision, not
    # the code's.
    it "does not call OSRM at all" do
      stub = stub_osrm

      route = resolve

      expect(stub).not_to have_been_requested
      expect(route).to be_straight_line
    end

    it "still returns a usable distance and duration" do
      route = resolve

      expect(route.distance_km).to be_within(0.5).of(4.3)
      expect(route.duration_minutes).to eq(Geo::Distance.travel_minutes(route.distance_km))
    end

    it "has no geometry, which the app renders as a plain line between pins" do
      expect(resolve.geometry).to be_nil
    end
  end

  describe "with OSRM enabled" do
    before { enable_osrm! }

    it "takes the distance from the road network" do
      stub_osrm(distance_m: 5698.8)

      route = resolve

      expect(route).to be_osrm
      expect(route.distance_km).to eq(5.699)
    end

    # A straight line genuinely under-measures: the road is longer. That is the
    # whole reason to adopt it.
    it "reports a longer distance than the straight line for the same pins" do
      stub_osrm(distance_m: 5698.8)

      routed = resolve
      straight = Geo::Distance.km(from_lat: from[:lat], from_lng: from[:lng],
                                  to_lat: to[:lat], to_lng: to[:lng])

      expect(routed.distance_km).to be > straight
    end

    # THE ONE LINE THAT KEEPS eta_average_speed_kmh MEANING WHAT IT SAYS.
    # OSRM's durations imply 49-69 km/h across Kabul because car.lua is
    # free-flow and Afghan maxspeed tags are sparse. Taking them would swap a
    # known error for an uncalibrated one.
    it "IGNORES OSRM's duration and recomputes from the calibratable setting" do
      stub_osrm(distance_m: 5698.8, duration_s: 394.7)

      route = resolve

      # OSRM said 6.6 minutes; at the configured 18 km/h, 5.699 km is 19.
      expect(route.duration_minutes).to eq(Geo::Distance.travel_minutes(5.699))
      expect(route.duration_minutes).to eq(19)
      expect(route.duration_minutes).not_to eq(7)
    end

    it "carries the drawn line and the snap distances" do
      stub_osrm

      route = resolve

      expect(route.geometry["type"]).to eq("LineString")
      expect(route.origin_snap_metres).to eq(30.0)
      expect(route.destination_snap_metres).to eq(40.0)
    end
  end

  describe "falling back, which is correctness and not politeness" do
    before { enable_osrm! }

    # AN ORDER MUST NEVER FAIL BECAUSE ROUTING IS DOWN. A quote degrades to a
    # straight line and says so, rather than refusing a customer at the confirm
    # button.
    it "falls back to a straight line when OSRM is unreachable" do
      stub_request(:get, %r{#{Regexp.escape(base)}}).to_raise(Errno::ECONNREFUSED)

      route = resolve

      expect(route).to be_straight_line
      expect(route.distance_km).to be_positive
    end

    it "falls back on a timeout" do
      stub_request(:get, %r{#{Regexp.escape(base)}}).to_timeout

      expect(resolve).to be_straight_line
    end

    it "falls back when OSRM finds no route" do
      stub_request(:get, %r{#{Regexp.escape(base)}})
        .to_return(body: { code: "NoRoute", routes: [] }.to_json)

      expect(resolve).to be_straight_line
    end

    it "falls back on a 500" do
      stub_request(:get, %r{#{Regexp.escape(base)}}).to_return(status: 500, body: "")

      expect(resolve).to be_straight_line
    end

    # Reported, never swallowed silently: a permanently unreachable router
    # would otherwise look like nothing at all while every fare quietly changed
    # method.
    it "logs the fallback so a broken router is visible" do
      stub_request(:get, %r{#{Regexp.escape(base)}}).to_raise(Errno::ECONNREFUSED)
      allow(Rails.logger).to receive(:warn)

      resolve

      expect(Rails.logger).to have_received(:warn).with(/falling back to straight line/)
    end

    it "returns nil rather than guessing when a coordinate is missing entirely" do
      route = described_class.new(from_lat: nil, from_lng: 69.17,
                                  to_lat: 34.56, to_lng: 69.21).call

      expect(route).to be_nil
    end
  end

  describe "#pin_far_from_road?" do
    before { enable_osrm! }

    # Kabul is full of walled compounds; the measured worst case was a pin
    # inside the airport perimeter, 357 m from any mapped road.
    it "is true when a pin is far from the mapped network" do
      stub_request(:get, %r{#{Regexp.escape(base)}}).to_return(
        body: { code: "Ok",
                routes: [ { distance: 100.0, duration: 60.0, geometry: { type: "LineString", coordinates: [] } } ],
                waypoints: [ { distance: 357.2 }, { distance: 20.0 } ] }.to_json
      )

      expect(resolve).to be_pin_far_from_road
    end

    it "is false for pins on a road" do
      stub_osrm

      expect(resolve).not_to be_pin_far_from_road
    end

    it "is false on the straight-line fallback, which snaps nothing" do
      stub_request(:get, %r{#{Regexp.escape(base)}}).to_timeout

      expect(resolve).not_to be_pin_far_from_road
    end

    it "is tunable without a deploy" do
      stub_osrm
      Setting.find_by!(key: "routing_snap_warning_metres").update!(value: "10.0")

      expect(resolve).to be_pin_far_from_road
    end
  end
end
