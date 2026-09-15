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

    private

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
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED,
           Errno::EHOSTUNREACH, IOError => e
      raise Unavailable, "OSRM unreachable: #{e.class}"
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
