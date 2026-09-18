require "rails_helper"

# ═══ THE DRAWN LINE, BY ROAD ═══════════════════════════════════════════════
#
# Hamma9900 asked why the map still draws a dashed straight line when the
# decision was to draw the nearest way by road. The answer was a missing door,
# not a missing feature: the client, the serializer and the app's LineString
# were all built, and the app was fetching `${MAP_URL}/route/v1/driving/…` —
# the MAP host — while OSRM runs as an API accessory on 127.0.0.1:5000.
#
# ── WHY THE HAPPY PATH USES A RECORDED REAL RESPONSE ─────────────────────
#
# The hard part of testing this is telling a road from a straight line. A
# hand-written stub cannot do it: if I invent the geometry, then "the road is
# longer than the crow flight" is an assertion about a number I chose, which is
# the sixth shape — an instrument pointed at a value that cannot be wrong.
#
# So `spec/fixtures/files/osrm_kabul_route.json` is a REAL response, captured
# from the running router on 2026-09-18:
#
#   curl "http://localhost:5000/route/v1/driving/\
#   69.1750,34.5400;69.2123,34.5658?overview=full&geometries=geojson"
#
# Shar-e-Naw to the airport: 5525.6 m over 146 geometry points, against 4.461 km
# straight line — a ratio of 1.24, at the bottom of the 1.24–1.47 band measured
# across Kabul. **Both sides of that comparison are computed here rather than
# typed**, so the assertion is about the data and not about my arithmetic.
RSpec.describe "Api::V1::Routes", type: :request do
  def json
    JSON.parse(response.body)
  end

  let(:user) { create(:user, :customer) }
  let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(user).last}" } }

  # Shar-e-Naw → Kabul airport, the pair the fixture was captured for.
  let(:from) { { latitude: 34.5400, longitude: 69.1750 } }
  let(:to) { { latitude: 34.5658, longitude: 69.2123 } }
  let(:pins) { { from_latitude: from[:latitude], from_longitude: from[:longitude],
                 to_latitude: to[:latitude], to_longitude: to[:longitude] } }

  let(:recorded) { Rails.root.join("spec/fixtures/files/osrm_kabul_route.json").read }
  let(:osrm) { %r{karwan_osrm:5000/route/v1/driving/} }

  # THE SUITE OPTS IN, per `spec/support/routing_default.rb`: the production
  # default is `osrm`, but specs write `straight_line` per example so hundreds
  # of them do not quietly exercise the failure path while looking like the
  # happy one. Copied from `spec/services/routing/distance_resolver_spec.rb:13`.
  def enable_osrm!
    Setting.seed_defaults!
    Setting.find_by!(key: "routing_distance_source").update!(value: "osrm")
  end

  def ask(params = pins, headers: auth)
    get "/api/v1/route", params: params, headers: headers
  end

  describe "when the router answers" do
    before do
      enable_osrm!
      stub_request(:get, osrm).to_return(status: 200, body: recorded)
    end

    it "returns a road line, not a straight one" do
      ask

      expect(response).to have_http_status(:ok)
      route = json["route"]
      expect(route["source"]).to eq("osrm")

      coordinates = route.dig("geometry", "coordinates")
      # > 2 is the real test. `geometry.present?` passes the moment anybody
      # synthesises a two-point line, and a two-point line IS the straight
      # line wearing a costume.
      expect(coordinates.size).to be > 2
      expect(coordinates.size).to eq(146)
    end

    # THE ASSERTION THAT CANNOT BE SATISFIED BY A FALLBACK, with both sides
    # derived: the straight line is computed from the same two pins by the same
    # helper the fallback would use.
    it "measures further by road than the crow flies, for the same two pins" do
      straight = Geo::Distance.km(from_lat: from[:latitude], from_lng: from[:longitude],
                                  to_lat: to[:latitude], to_lng: to[:longitude])

      ask

      road = json.dig("route", "distance_km").to_f
      expect(road).to be > straight
      # The measured Kabul band. A road that EQUALS the crow flight is the
      # fallback mislabelled, and a road 3x longer is a routing error.
      expect(road / straight).to be_between(1.15, 1.6)
    end

    # Real data carries this: the airport pin is 548.9 m from any mapped road,
    # well over the 150 m warning threshold. The landmark note and the phone
    # number are doing the real work for that drop, and the app is told so.
    it "flags a pin that is not on the road network" do
      ask

      expect(json.dig("route", "pin_far_from_road")).to be true
    end

    it "carries a duration the app can show" do
      ask

      expect(json.dig("route", "duration_minutes")).to be_positive
    end
  end

  # ── THE RULE THAT OUTRANKS THE FEATURE ───────────────────────────────────
  #
  # MAP_AND_ROUTING.md §Rules: an order must never fail because routing is down.
  # A 5xx here would take the map screen out for every role at once.
  describe "when the router is down" do
    # OSRM MUST BE ENABLED HERE. With it disabled the endpoint returns
    # `straight_line` without ever reaching for the router, and every assertion
    # below would pass for the wrong reason — the fallback has to be reached by
    # FALLING BACK, not by never having tried.
    before do
      enable_osrm!
      stub_request(:get, osrm).to_raise(Errno::ECONNREFUSED)
    end

    it "still answers 200, and says the line is a straight one" do
      ask

      expect(response).to have_http_status(:ok)
      expect(json.dig("route", "source")).to eq("straight_line")
      expect(json.dig("route", "distance_km").to_f).to be_positive
    end

    # NOT a synthesised two-point line. `RouteMap` already falls back to
    # [start, end] itself; a server-built "geometry" of two points would arrive
    # indistinguishable from a road and there would be nothing downstream able
    # to tell. The nil is the honest answer and the app is built for it.
    it "returns no geometry at all rather than inventing one" do
      ask

      expect(json["route"]).to have_key("geometry")
      expect(json.dig("route", "geometry")).to be_nil
    end
  end

  # ── IT IS A PROXY, AND THE CPU IS HAMMA9900'S ────────────────────────────
  describe "the coordinates it refuses" do
    # TEHRAN, not Peshawar. Peshawar is at 71.52°E, which is INSIDE
    # Afghanistan's bounding rectangle — the country's eastern tip reaches
    # 74.9°E in the Wakhan corridor, so any rectangle drawn round Afghanistan
    # necessarily swallows a strip of Pakistan. `Geo::Bounds` says so: it is a
    # COST bound against routing across continents, not a border. Testing it
    # with a coordinate it was never going to reject would have been an
    # instrument pointed at a value that cannot be wrong.
    it "refuses a pin outside the country, without asking the router" do
      enable_osrm!
      stub_request(:get, osrm).to_return(status: 200, body: recorded)

      ask(pins.merge(to_latitude: 35.6892, to_longitude: 51.3890)) # Tehran

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("outside_service_area")
      # The point of the bound is that it costs nothing. If the router is asked
      # first, the limit protects nobody.
      expect(a_request(:get, osrm)).not_to have_been_made
    end

    it "refuses a non-numeric coordinate rather than routing from nowhere" do
      ask(pins.merge(from_latitude: "here"))

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("outside_service_area")
    end
  end

  describe "the rate limit" do
    it "stops one account from using the router as a free service" do
      enable_osrm!
      stub_request(:get, osrm).to_return(status: 200, body: recorded)

      61.times { ask }

      expect(response).to have_http_status(:too_many_requests)
    end
  end
end
