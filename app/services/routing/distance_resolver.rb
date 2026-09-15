module Routing
  # How far apart two pins are, and by what method.
  #
  # OSRM when it is reachable AND enabled, straight-line otherwise. The
  # fallback is not a nicety: **an order must never fail because routing is
  # down.** A quote degrades to a straight line and says so, rather than
  # refusing a customer at the confirm button.
  #
  # WHETHER OSRM DISTANCE IS USED FOR MONEY IS A SETTING, defaulting to OFF.
  # The measurement is unambiguous — over eight real Kabul routes the
  # road/straight ratio runs 1.14 to 2.82, median 1.35, so a straight line
  # genuinely under-measures and no single average speed can absorb that
  # spread. But adopting it raises fares about 29%, which is Hamma9900's
  # decision and not the code's. A Setting means he says yes once and nothing
  # is deployed.
  #
  # Duration stays on `eta_average_speed_kmh` either way. OSRM's own durations
  # imply 49-69 km/h across Kabul because `car.lua` is free-flow and Afghan
  # maxspeed tags are sparse; taking them would swap a known error for an
  # uncalibrated one.
  class DistanceResolver
    def initialize(from_lat:, from_lng:, to_lat:, to_lng:, client: nil)
      @from_lat = from_lat
      @from_lng = from_lng
      @to_lat = to_lat
      @to_lng = to_lng
      @client = client
    end

    def call
      routed = routed_distance
      return routed if routed.present?

      straight_line
    end

    private

    def routed_distance
      return nil unless osrm_enabled?
      # Never call a router with incomplete input. A nil coordinate can only
      # produce a failed request, and the straight-line path below already
      # returns nil for the same reason — "we do not know where this is" is a
      # different answer from "it is zero kilometres away".
      return nil unless coordinates_present?

      route = client.route(from_lat: @from_lat, from_lng: @from_lng,
                           to_lat: @to_lat, to_lng: @to_lng)

      # Duration is recomputed from the calibratable setting, NOT taken from
      # OSRM. This is the one line that keeps `eta_average_speed_kmh` meaning
      # what its description says.
      route.with(duration_minutes: Geo::Distance.travel_minutes(route.distance_km))
    rescue OsrmClient::Error => e
      # Reported, never swallowed silently: a permanently unreachable router
      # would otherwise look like nothing at all while every fare quietly
      # changed method.
      Rails.logger.warn("[routing] falling back to straight line: #{e.class}: #{e.message}")
      nil
    end

    def straight_line
      km = Geo::Distance.km(from_lat: @from_lat, from_lng: @from_lng,
                            to_lat: @to_lat, to_lng: @to_lng)
      return nil if km.nil?

      Route.new(
        distance_km: km,
        duration_minutes: Geo::Distance.travel_minutes(km),
        source: Route::STRAIGHT_LINE,
        geometry: nil,
        origin_snap_metres: nil,
        destination_snap_metres: nil
      )
    end

    def coordinates_present?
      [ @from_lat, @from_lng, @to_lat, @to_lng ].none?(&:nil?)
    end

    def osrm_enabled?
      Setting.fetch("routing_distance_source") == Route::OSRM
    end

    def client
      @client ||= OsrmClient.new
    end
  end
end
