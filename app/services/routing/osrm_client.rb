require "net/http"
require "json"

module Routing
  # The only place that talks to OSRM.
  #
  # Container-to-container on the kamal network — `http://karwan_osrm:5000`, not
  # a public URL. Nothing is exposed through nginx, so there is no TLS, no CORS
  # and no Hatiwal config to touch.
  #
  # THE COORDINATE ORDER IS REVERSED FROM EVERY OTHER SIGNATURE IN THIS
  # CODEBASE. OSRM takes `lng,lat`; `Geo::Distance` takes `from_lat:, from_lng:`.
  # Swapping them does not error — it silently routes somewhere off the coast of
  # Somalia and returns a plausible number. So the flip happens exactly once, in
  # `path_for`, and a spec asserts it against a known Kabul pair.
  class OsrmClient
    Error = Class.new(StandardError)
    Unavailable = Class.new(Error)
    NoRoute = Class.new(Error)

    # FROM THE ENVIRONMENT, NOT FROM A SETTING.
    #
    # Brakeman flagged the previous version — a `Setting` row feeding an
    # outbound HTTP host is an SSRF surface, and it was right to. An admin who
    # can edit settings could repoint routing at any address and use the app to
    # probe the internal network.
    #
    # It also belongs in the environment on the merits: `Setting` rows are for
    # numbers Hamma9900 tunes weekly — commission, fees, the credit line. A
    # service address is infrastructure. The switch that decides WHETHER routed
    # distance is used for money stays a Setting, because that one is his
    # decision and must not need a deploy.
    DEFAULT_BASE_URL = "http://karwan_osrm:5000".freeze

    PROFILE = "driving".freeze
    # Turn-by-turn is not used — navigation is handed to the phone's maps app,
    # as in Hatiwal — and both of these multiply the payload.
    QUERY = { overview: "full", geometries: "geojson", steps: "false", annotations: "false" }.freeze

    def initialize(base_url: nil, open_timeout: nil, read_timeout: nil)
      @base_url = base_url || ENV.fetch("OSRM_BASE_URL", DEFAULT_BASE_URL)
      @open_timeout = open_timeout || Setting.fetch("routing_open_timeout_seconds")
      @read_timeout = read_timeout || Setting.fetch("routing_read_timeout_seconds")
    end

    def route(from_lat:, from_lng:, to_lat:, to_lng:)
      raise Unavailable, "no OSRM base url configured" if @base_url.blank?

      body = get(path_for(from_lat: from_lat, from_lng: from_lng, to_lat: to_lat, to_lng: to_lng))
      parse(body)
    end

    # ── MANY DESTINATIONS, ONE REQUEST ─────────────────────────────────────────
    #
    # The distance matrix, which is precisely what OSRM's `/table` exists for.
    # The customer's Home screen shows N merchants with a distance each; asking
    # `/route` N times would be N round trips for one screen, on a connection
    # where every request costs the user money.
    #
    # Returns metres from the ORIGIN to each destination, in the order given,
    # with `nil` where OSRM could not route. Never raises for one unroutable
    # destination: a single walled compound must not blank the whole list.
    def table(origin_lat:, origin_lng:, destinations:)
      raise Unavailable, "no OSRM base url configured" if @base_url.blank?
      return [] if destinations.empty?

      body = get(table_path_for(origin_lat: origin_lat, origin_lng: origin_lng,
                                destinations: destinations))
      parse_table(body, destinations.size)
    end

    private

    def table_path_for(origin_lat:, origin_lng:, destinations:)
      # `lng,lat`, which is OSRM's order and the reverse of everything else in
      # this codebase — the class comment says why that is worth shouting
      # about: swapping them does not error, it silently routes off the coast.
      points = [ [ origin_lng, origin_lat ] ]
                 .concat(destinations.map { |d| [ d[:longitude], d[:latitude] ] })
                 .map { |lng, lat| "#{lng},#{lat}" }.join(";")

      # `sources=0` — one row, from the customer. Asking for the full N×N
      # matrix would be quadratic work for a column we never read.
      #
      # `annotations=distance`, not duration: the duration is OURS, from
      # `eta_average_speed_kmh`, because OSRM's `car.lua` is free-flow and
      # implies 43–69 km/h across Kabul.
      query = URI.encode_www_form(sources: 0, annotations: "distance")

      "/table/v1/#{PROFILE}/#{points}?#{query}"
    end

    # The first row of the matrix, minus its own zero-distance self.
    def parse_table(body, expected)
      payload = JSON.parse(body)
      return nil unless payload["code"] == "Ok"

      row = payload.dig("distances", 0)
      return nil unless row.is_a?(Array) && row.size == expected + 1

      row.drop(1).map { |metres| metres.is_a?(Numeric) ? metres : nil }
    rescue JSON::ParserError
      nil
    end

    # THE FLIP, in one place.
    def path_for(from_lat:, from_lng:, to_lat:, to_lng:)
      coordinates = "#{from_lng},#{from_lat};#{to_lng},#{to_lat}"
      query = URI.encode_www_form(QUERY)

      "/route/v1/#{PROFILE}/#{coordinates}?#{query}"
    end

    def get(path)
      uri = validated_uri(path)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      # ~500x the measured p95 (3.9 ms) and still not a hang. Deliberately no
      # retry: a customer waiting on a confirm button would rather have a
      # straight-line quote now than a routed one in six seconds.
      http.open_timeout = @open_timeout
      http.read_timeout = @read_timeout

      response = http.request(Net::HTTP::Get.new(uri.request_uri))
      raise Unavailable, "OSRM returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      response.body
    # ── A NAMED LIST FIRST, THEN A CATCH-ALL, and the catch-all is deliberate ──
    #
    # The named errors are what an unreachable router actually raises and are
    # worth naming so the log says which. But the CONTRACT of this client is
    # that a quote never fails because of it: `DistanceResolver` falls back to
    # a straight line and records that it did.
    #
    # So anything else — a DNS resolver returning something odd, an SSL error,
    # a library raising a class nobody predicted — must degrade too. A
    # customer's cart 500ing at the confirm button because a routing container
    # hiccuped is a lost order, and routing is an IMPROVEMENT to a fare rather
    # than a requirement of one.
    #
    # It surfaced in the suite the moment routed distance became the default:
    # WebMock raises its own error class for an unstubbed request, which no
    # named list would ever have contained.
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED,
           Errno::EHOSTUNREACH, IOError => e
      raise Unavailable, "OSRM unreachable: #{e.class}"
    rescue Error
      # OUR OWN ERRORS PASS THROUGH UNTOUCHED, and this clause is here because
      # the catch-all below swallowed them: the SSRF guard raises `Unavailable`
      # with a message naming what was wrong with the address, and wrapping it
      # turned "the base url must be http or https" into "OSRM call failed",
      # which is the difference between a deploy typo somebody can fix and a
      # mystery. Its own specs caught it.
      raise
    rescue StandardError => e
      raise Unavailable, "OSRM call failed: #{e.class}"
    end

    # Checked rather than trusted, even though the value now comes from the
    # environment: a typo in a deploy variable should fail with a clear message
    # rather than as an obscure Net::HTTP error, and only plain HTTP to a named
    # host is ever intended here.
    def validated_uri(path)
      # Validate the BASE before joining. `URI.join` on a non-HTTP base raises
      # from inside URI itself — an ftp base dies on `typecode` with a
      # NoMethodError — so checking the joined result was too late to produce a
      # useful message.
      base = URI.parse(@base_url)
      raise Unavailable, "OSRM address must be http or https" unless base.is_a?(URI::HTTP)
      raise Unavailable, "OSRM address has no host" if base.host.blank?
      raise Unavailable, "OSRM address must not carry credentials" if base.userinfo.present?

      URI.join(base, path)
    rescue URI::InvalidURIError
      raise Unavailable, "OSRM address is not a valid URL"
    end

    def parse(body)
      payload = JSON.parse(body)

      # `NoRoute` arrives with HTTP 200, so a status check alone would happily
      # price a ride at zero kilometres. Check `code`, THEN check there is
      # actually a route.
      raise NoRoute, "OSRM code #{payload['code']}" unless payload["code"] == "Ok"

      route = payload["routes"]&.first
      raise NoRoute, "OSRM returned no routes" if route.blank?

      snaps = Array(payload["waypoints"]).map { |waypoint| waypoint["distance"] }

      Route.new(
        distance_km: (route.fetch("distance") / 1000.0).round(3),
        # Carried for completeness and NOT used for pricing — see
        # Routing::DistanceResolver.
        duration_minutes: (route.fetch("duration") / 60.0).ceil,
        source: Route::OSRM,
        geometry: route["geometry"],
        origin_snap_metres: snaps[0]&.round(1),
        destination_snap_metres: snaps[1]&.round(1)
      )
    rescue JSON::ParserError, KeyError => e
      raise NoRoute, "unreadable OSRM response: #{e.class}"
    end
  end
end
