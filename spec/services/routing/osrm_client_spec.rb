require "rails_helper"

RSpec.describe Routing::OsrmClient do
  # Shar-e-Naw to Kabul airport. Real coordinates, because the whole risk in
  # this client is the coordinate order.
  let(:from) { { lat: 34.5400, lng: 69.1750 } }
  let(:to) { { lat: 34.5658, lng: 69.2123 } }
  let(:base) { "http://karwan_osrm:5000" }

  def ok_body(distance: 5698.8, duration: 394.7, snaps: [ 79.8, 23.7 ])
    {
      code: "Ok",
      routes: [ {
        distance: distance, duration: duration,
        geometry: { type: "LineString", coordinates: [ [ 69.169703, 34.532577 ], [ 69.2123, 34.5658 ] ] }
      } ],
      waypoints: snaps.map { |d| { distance: d } }
    }.to_json
  end

  def route!
    described_class.new.route(from_lat: from[:lat], from_lng: from[:lng],
                              to_lat: to[:lat], to_lng: to[:lng])
  end

  describe "the request" do
    # THE ONE THING THAT MUST BE RIGHT. OSRM takes lng,lat — the reverse of
    # every other signature in this codebase. Swapping them does not error; it
    # silently routes somewhere off Somalia and returns a plausible number, so
    # only an assertion on the URL catches it.
    it "sends coordinates as lng,lat — not lat,lng" do
      stub = stub_request(:get, %r{\A#{Regexp.escape(base)}/route/v1/driving/})
             .to_return(body: ok_body, headers: { "Content-Type" => "application/json" })

      route!

      expect(stub).to have_been_requested
      expect(WebMock).to have_requested(:get, %r{/driving/69\.175,34\.54;69\.2123,34\.5658})
    end

    it "asks for a full geojson line and nothing it does not use" do
      stub_request(:get, %r{#{Regexp.escape(base)}}).to_return(body: ok_body)

      route!

      expect(WebMock).to have_requested(:get, %r{overview=full})
      expect(WebMock).to have_requested(:get, %r{geometries=geojson})
      # Turn-by-turn is handed to the phone's maps app, and both of these
      # multiply the payload.
      expect(WebMock).to have_requested(:get, %r{steps=false})
      expect(WebMock).to have_requested(:get, %r{annotations=false})
    end

    it "uses the driving profile, the only one the engine is built with" do
      stub_request(:get, %r{#{Regexp.escape(base)}}).to_return(body: ok_body)

      route!

      expect(WebMock).to have_requested(:get, %r{/route/v1/driving/})
    end

    # A service name on the deploy network, never a public URL — nothing is
    # exposed through nginx.
    it "calls the container, not the internet" do
      stub_request(:get, %r{#{Regexp.escape(base)}}).to_return(body: ok_body)

      route!

      expect(WebMock).to have_requested(:get, %r{\Ahttp://karwan_osrm:5000/})
    end
  end

  describe "the response" do
    before { stub_request(:get, %r{#{Regexp.escape(base)}}).to_return(body: ok_body) }

    it "converts metres to kilometres" do
      expect(route!.distance_km).to eq(5.699)
    end

    it "converts seconds to minutes, rounded up" do
      expect(route!.duration_minutes).to eq(7)
    end

    it "returns the geometry MapLibre will draw, untouched" do
      geometry = route!.geometry

      expect(geometry["type"]).to eq("LineString")
      expect(geometry["coordinates"].first).to eq([ 69.169703, 34.532577 ])
    end

    # How far OSRM moved each pin to reach a road. When a courier says "the app
    # sent me to the wrong gate", this is the answer.
    it "records how far each pin was snapped" do
      expect(route!.origin_snap_metres).to eq(79.8)
      expect(route!.destination_snap_metres).to eq(23.7)
    end

    it "marks the source as osrm" do
      expect(route!).to be_osrm
    end
  end

  describe "failures, all of which must fall back rather than raise upward" do
    # `NoRoute` arrives with HTTP 200, so a status check alone would happily
    # price a ride at zero kilometres.
    it "treats a non-Ok code as a miss even on HTTP 200" do
      stub_request(:get, %r{#{Regexp.escape(base)}})
        .to_return(status: 200, body: { code: "NoRoute", routes: [] }.to_json)

      expect { route! }.to raise_error(described_class::NoRoute)
    end

    it "treats an empty routes array as a miss" do
      stub_request(:get, %r{#{Regexp.escape(base)}})
        .to_return(status: 200, body: { code: "Ok", routes: [] }.to_json)

      expect { route! }.to raise_error(described_class::NoRoute)
    end

    it "treats unreadable JSON as a miss, not a crash" do
      stub_request(:get, %r{#{Regexp.escape(base)}}).to_return(body: "<html>nope</html>")

      expect { route! }.to raise_error(described_class::NoRoute)
    end

    it "treats a 500 as unavailable" do
      stub_request(:get, %r{#{Regexp.escape(base)}}).to_return(status: 500, body: "")

      expect { route! }.to raise_error(described_class::Unavailable)
    end

    it "treats a refused connection as unavailable" do
      stub_request(:get, %r{#{Regexp.escape(base)}}).to_raise(Errno::ECONNREFUSED)

      expect { route! }.to raise_error(described_class::Unavailable)
    end

    it "treats a timeout as unavailable rather than hanging" do
      stub_request(:get, %r{#{Regexp.escape(base)}}).to_timeout

      expect { route! }.to raise_error(described_class::Unavailable)
    end

    it "refuses to call at all with no address configured" do
      client = described_class.new(base_url: "")

      expect {
        client.route(from_lat: from[:lat], from_lng: from[:lng],
                     to_lat: to[:lat], to_lng: to[:lng])
      }.to raise_error(described_class::Unavailable, /no OSRM base url/)
    end

    # The address now comes from the environment rather than a Setting, because
    # a Setting feeding an outbound host is an SSRF surface. It is still
    # checked, so a typo in a deploy variable fails clearly.
    it "refuses a non-http address" do
      client = described_class.new(base_url: "ftp://somewhere/")

      expect {
        client.route(from_lat: from[:lat], from_lng: from[:lng],
                     to_lat: to[:lat], to_lng: to[:lng])
      }.to raise_error(described_class::Unavailable, /http or https/)
    end

    it "refuses an address carrying credentials" do
      client = described_class.new(base_url: "http://user:pass@karwan_osrm:5000/")

      expect {
        client.route(from_lat: from[:lat], from_lng: from[:lng],
                     to_lat: to[:lat], to_lng: to[:lng])
      }.to raise_error(described_class::Unavailable, /credentials/)
    end
  end

  describe "timeouts" do
    # ~500x the measured p95 of 3.9 ms, and deliberately no retry: a customer
    # on a confirm button would rather have a straight-line quote now than a
    # routed one in six seconds.
    it "takes the address from the environment, defaulting to the service name" do
      expect(described_class::DEFAULT_BASE_URL).to eq("http://karwan_osrm:5000")
    end

    it "defaults to the configured short timeouts" do
      client = described_class.new

      expect(client.send(:instance_variable_get, :@open_timeout)).to eq(1)
      expect(client.send(:instance_variable_get, :@read_timeout)).to eq(2)
    end

    it "does not retry" do
      stub = stub_request(:get, %r{#{Regexp.escape(base)}}).to_timeout

      expect { route! }.to raise_error(described_class::Unavailable)
      expect(stub).to have_been_requested.once
    end
  end
end
