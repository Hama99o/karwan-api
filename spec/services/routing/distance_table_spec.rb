require "rails_helper"

# ROAD DISTANCES FOR A WHOLE LIST.
#
# Hamma9900 looked at the app and said distances are not measured by roads.
# He was right twice, and the second was worse: the QUOTE went through
# `DistanceResolver` while every DISPLAYED distance called `Geo::Distance.km`
# directly — so **the card said 3.6 km and the fare was computed from 4.6 km.**
# A customer shown a number that was not true is not repaired by correct
# arithmetic afterwards.
RSpec.describe Routing::DistanceTable do
  let(:base) { "http://karwan_osrm:5000" }
  let(:origin) { { lat: 34.5400, lng: 69.1750 } }

  # Three real Kabul destinations, in the order the matrix returns them.
  let(:destinations) do
    [
      { key: :airport, latitude: 34.5658, longitude: 69.2123 },
      { key: :karte_naw, latitude: 34.5100, longitude: 69.1900 },
      { key: :macroryan, latitude: 34.5450, longitude: 69.2350 }
    ]
  end

  def enable_osrm!
    Setting.find_by!(key: "routing_distance_source").update!(value: "osrm")
  end

  def stub_table(distances:)
    stub_request(:get, %r{#{Regexp.escape(base)}/table/v1/})
      .to_return(body: { code: "Ok", distances: [ [ 0.0, *distances ] ] }.to_json)
  end

  def result(list = destinations)
    described_class.new(origin_lat: origin[:lat], origin_lng: origin[:lng],
                        destinations: list).call
  end

  describe "when the router answers" do
    before { enable_osrm! }

    it "asks ONE question for the whole list" do
      stub_table(distances: [ 5525.6, 4600.5, 6863.8 ])

      result

      expect(a_request(:get, %r{#{Regexp.escape(base)}/table/v1/})).to have_been_made.once
    end

    it "returns road kilometres per key, and says they are routed" do
      stub_table(distances: [ 5525.6, 4600.5, 6863.8 ])

      table = result

      expect(table.source).to eq("osrm")
      expect(table.km(:airport)).to eq(5.526)
      expect(table.km(:karte_naw)).to eq(4.601)
    end

    # THE MEASURED DIFFERENCE, which is the point: the straight line
    # under-measures, and the customer was being shown the smaller number.
    it "reports a longer distance than the straight line for the same pins" do
      stub_table(distances: [ 5525.6, 4600.5, 6863.8 ])
      straight = Geo::Distance.km(from_lat: origin[:lat], from_lng: origin[:lng],
                                  to_lat: 34.5658, to_lng: 69.2123)

      expect(result.km(:airport)).to be > straight
    end

    it "asks for distance only — the duration is ours, from the calibratable setting" do
      stub_table(distances: [ 1000.0, 1000.0, 1000.0 ])

      result

      expect(a_request(:get, %r{annotations=distance})).to have_been_made
      expect(a_request(:get, %r{annotations=duration})).not_to have_been_made
    end

    # ONE unroutable pin — a walled compound, an unmapped lane — is an ABSENCE,
    # not a failure. The app already renders a missing distance, and the list's
    # source stays honest.
    it "leaves one unroutable destination without a distance, and keeps the rest" do
      stub_table(distances: [ 5525.6, nil, 6863.8 ])

      table = result

      expect(table.km(:karte_naw)).to be_nil
      expect(table.km(:airport)).to eq(5.526)
      expect(table.source).to eq("osrm")
    end
  end

  describe "when the router cannot be reached" do
    before { enable_osrm! }

    # ── PER LIST, NEVER PER ROW ──────────────────────────────────────────────
    #
    # A mixture would have the customer sorting road distances against
    # crow-flight ones without being told which was which.
    it "falls back to straight line for the WHOLE list, and says so" do
      stub_request(:get, %r{#{Regexp.escape(base)}/table/v1/}).to_raise(Errno::ECONNREFUSED)

      table = result

      expect(table.source).to eq("straight_line")
      # A fallback that produced NO distances also reports "straight_line", and
      # `all` passes on an empty table — so the whole-list claim needs the list.
      expect(table.km_by_key).not_to be_empty, "empty table — the assertion below would be vacuous"
      expect(table.km_by_key.values).to all(be_positive)
    end

    it "falls back on a malformed answer rather than showing nothing" do
      stub_request(:get, %r{#{Regexp.escape(base)}/table/v1/})
        .to_return(body: { code: "NoRoute" }.to_json)

      expect(result.source).to eq("straight_line")
    end

    it "falls back when the matrix is the wrong shape" do
      # One row short: a payload we cannot trust is a payload we do not use.
      stub_table(distances: [ 5525.6 ])

      expect(result.source).to eq("straight_line")
    end
  end

  describe "when routing is switched off" do
    it "does not call the router at all" do
      Setting.find_by!(key: "routing_distance_source").update!(value: "straight_line")

      table = result

      expect(table.source).to eq("straight_line")
      expect(a_request(:get, %r{#{Regexp.escape(base)}})).not_to have_been_made
    end
  end

  describe "the cap" do
    before { enable_osrm! }

    # A paginated screen never reaches this — `MAX_PAGE_SIZE` is 100 — so the
    # cap exists so an unbounded caller degrades predictably rather than
    # building a five-thousand-point URL.
    it "asks about the nearest ones only, and leaves the rest without a distance" do
      many = (1..described_class::MAX_DESTINATIONS + 5).map do |i|
        { key: i, latitude: 34.54 + (i * 0.001), longitude: 69.175 }
      end
      stub_table(distances: Array.new(described_class::MAX_DESTINATIONS, 1000.0))

      table = result(many)

      expect(table.km(1)).to eq(1.0)
      expect(table.km(many.last[:key])).to be_nil
    end
  end

  describe "with nothing to measure" do
    it "is empty rather than a request" do
      table = described_class.new(origin_lat: nil, origin_lng: nil, destinations: destinations).call

      expect(table.km_by_key).to be_empty
      expect(a_request(:get, %r{#{Regexp.escape(base)}})).not_to have_been_made
    end

    it "handles a destination with no pin at all" do
      table = result([ { key: :nowhere, latitude: nil, longitude: nil } ])

      expect(table.km_by_key).to be_empty
    end
  end
end
