module Routing
  # ROAD DISTANCES FOR A WHOLE LIST, in one request.
  #
  # ── THE BUG THIS EXISTS TO FIX ────────────────────────────────────────────
  # Hamma9900 looked at the app and said distances are not measured by roads,
  # and that straight-line is unfair. He was right twice, and the second was
  # worse than the first: the QUOTE went through `DistanceResolver` while every
  # DISPLAYED distance called `Geo::Distance.km` directly. So the card on Home
  # said 3.6 km and the fare was computed from 4.6 km.
  #
  # **That is worse than being consistently wrong.** A customer who reads 3.6 km
  # and is charged against 4.6 km has been shown a number that was not true,
  # and no amount of correct arithmetic afterwards repairs it.
  #
  # ── ONE REQUEST, NOT N ────────────────────────────────────────────────────
  # OSRM's `/table` is precisely this: a matrix from one origin to many
  # destinations. Asking `/route` per merchant would be N round trips for one
  # screen, on a connection where every request costs the user money — and
  # self-hosted, it costs us nothing per request either way.
  #
  # ── FALL BACK PER LIST, NEVER PER ROW ─────────────────────────────────────
  # If the router is unreachable the WHOLE list reverts to straight-line and
  # says so. A mixture would make two cards incomparable: the customer would be
  # sorting road distances against crow-flight ones without being told.
  #
  # A single UNROUTABLE destination is different from a failure, and is treated
  # differently: that card gets no distance at all (the app already renders a
  # missing one), and the list's source stays `osrm`. An absence is honest; a
  # silently substituted number is not.
  class DistanceTable
    # What we are willing to put in one URL. A paginated screen never reaches
    # this — `MAX_PAGE_SIZE` is 100 — so it exists so that an unbounded caller
    # degrades predictably instead of building a five-thousand-point request.
    # Beyond it, the nearest by straight line are asked about and the rest get
    # no distance rather than a differently-sourced one.
    MAX_DESTINATIONS = 200

    # `km_by_key` holds a Float or nil per key; `source` describes the whole
    # list, because that is the unit the fallback works in.
    Result = Data.define(:source, :km_by_key) do
      def osrm?
        source == Route::OSRM
      end

      def km(key)
        km_by_key[key]
      end
    end

    def initialize(origin_lat:, origin_lng:, destinations:, client: nil)
      @origin_lat = origin_lat
      @origin_lng = origin_lng
      # [{ key:, latitude:, longitude: }]
      @destinations = Array(destinations).select { |d| d[:latitude].present? && d[:longitude].present? }
      @client = client
    end

    def call
      return empty if @origin_lat.blank? || @origin_lng.blank? || @destinations.empty?
      return straight_line unless osrm_enabled?

      routed || straight_line
    end

    private

    def osrm_enabled?
      Setting.fetch("routing_distance_source") == Route::OSRM
    end

    # Nil — meaning "use the fallback" — on any failure of the whole call.
    def routed
      asked = nearest_within_cap
      metres = client.table(origin_lat: @origin_lat, origin_lng: @origin_lng,
                            destinations: asked.map { |d| d.slice(:latitude, :longitude) })
      return nil if metres.nil?

      km_by_key = asked.each_with_index.to_h do |destination, index|
        value = metres[index]
        [ destination[:key], value.nil? ? nil : (value / 1000.0).round(3) ]
      end
      # Anything beyond the cap has no distance rather than a straight-line one.
      Result.new(source: Route::OSRM, km_by_key: default_nils.merge(km_by_key))
    rescue OsrmClient::Unavailable, OsrmClient::Error => e
      # Logged, because a silently degraded list is how a routed fare and an
      # unrouted card drift apart without anybody noticing.
      Rails.logger.warn("[routing] table unavailable, falling back to straight line: #{e.class}")
      nil
    end

    # Straight line is a perfectly good PRE-FILTER; it is only a bad final
    # answer. So the nearest N by crow flight are the ones we ask about.
    def nearest_within_cap
      return @destinations if @destinations.size <= MAX_DESTINATIONS

      @destinations.sort_by { |d| straight_km(d) || Float::INFINITY }.first(MAX_DESTINATIONS)
    end

    def straight_line
      Result.new(
        source: Route::STRAIGHT_LINE,
        km_by_key: @destinations.to_h { |d| [ d[:key], straight_km(d) ] }
      )
    end

    def straight_km(destination)
      Geo::Distance.km(from_lat: @origin_lat, from_lng: @origin_lng,
                       to_lat: destination[:latitude], to_lng: destination[:longitude])
    end

    def default_nils
      @destinations.to_h { |d| [ d[:key], nil ] }
    end

    def empty
      Result.new(source: Route::STRAIGHT_LINE, km_by_key: {})
    end

    def client
      @client ||= OsrmClient.new
    end
  end
end
