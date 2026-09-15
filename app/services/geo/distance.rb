module Geo
  # Straight-line (great-circle) distance between two pins.
  #
  # DELIBERATELY not a routed distance. v0 has no routing engine — CLAUDE.md is
  # explicit that ETA is "straight-line distance / average speed, calibrated
  # from real deliveries", and that OSRM comes later only if it ever becomes the
  # bottleneck. A router would also be a third consumer of the map extract and a
  # service to run, against a per-order marginal cost that must stay at zero.
  #
  # The systematic error is known and accounted for rather than ignored: a real
  # route through a city is longer than the crow flies, typically by 20-40%.
  # That factor is absorbed into `eta_average_speed_kmh`, which is a tunable
  # setting precisely so it can be calibrated against real deliveries instead of
  # guessed. Lower the speed and both the ETA and any distance-based fee
  # stretch to match reality.
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
