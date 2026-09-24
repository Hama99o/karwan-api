module Geo
  # Straight-line (great-circle) distance between two pins.
  #
  # Written when v0 had no router, and the header said so — it said "OSRM comes
  # later", that a route runs "20-40%" longer, and that lowering the speed
  # setting stretched "any distance-based fee". None of that is true now:
  #
  #   * OSRM is on, by Hamma9900's decision (`748c135`), and a fee's distance is
  #     the ROAD distance from `Routing::DistanceResolver`. This module is its
  #     fallback when the router is off or unreachable.
  #   * Measured over 600 realistic Kabul pairs on 24 Sept 2026, a road runs a
  #     median 1.60x the straight line, p99 3.6x — not 20-40%.
  #   * `eta_average_speed_kmh` divides a distance into minutes. It has never
  #     touched a fee.
  #
  # What stays straight-line on purpose: dispatch's "who is nearest" and its
  # radius, the distance to the shop printed on a courier's offer, the courier
  # top-up's dead leg, and the live leg from a courier's reported position to
  # the customer — each a comparison or an estimate on a hot path, where a
  # routing round trip per candidate would cost more than the precision is
  # worth. Nothing here is what a customer is charged for.
  class Distance
    # Mean Earth radius (IUGG). At Kabul's scale the difference between this and
    # a proper ellipsoid is centimetres — far below the error already introduced
    # by using a straight line at all.
    EARTH_RADIUS_KM = 6371.0088

    class << self
      # Returns kilometres as a Float, rounded to 3 places (metre precision).
      # Nil for a missing coordinate rather than 0, because "we do not know
      # where this is" and "it is zero kilometres away" are different answers
      # and a zero would silently price a job at the minimum.
      def km(from_lat:, from_lng:, to_lat:, to_lng:)
        return nil if [ from_lat, from_lng, to_lat, to_lng ].any?(&:nil?)

        lat1 = to_radians(from_lat)
        lat2 = to_radians(to_lat)
        delta_lat = lat2 - lat1
        delta_lng = to_radians(to_lng) - to_radians(from_lng)

        a = (Math.sin(delta_lat / 2)**2) +
            (Math.cos(lat1) * Math.cos(lat2) * (Math.sin(delta_lng / 2)**2))

        (2 * EARTH_RADIUS_KM * Math.asin(Math.sqrt([ a, 1.0 ].min))).round(3)
      end

      # Minutes to cover a distance at the configured average speed. Ceiled,
      # because telling someone 14 minutes when it is 14.2 reads as late.
      def travel_minutes(km, speed_kmh: nil)
        return nil if km.nil?

        speed = speed_kmh || Setting.fetch("eta_average_speed_kmh")
        return nil if speed.to_f <= 0

        ((km / speed.to_f) * 60).ceil
      end
    end

    def self.to_radians(degrees)
      degrees.to_f * Math::PI / 180
    end
    private_class_method :to_radians
  end
end
