module Routing
  # ORDERS WHOSE ROAD WAS MUCH LONGER THAN THE STRAIGHT LINE — measured on
  # real orders, from what each order already recorded.
  #
  # Measured on 600 realistic Kabul pairs on 24 Sept 2026: a road runs a median
  # 1.60x the straight line, and 3.8% run past 3x. The worst priced a delivery
  # between two pins 2.35 km apart at 366 AFN instead of 97, on a route that
  # loops out along the Jalalabad road and back — by the look of it a gap in
  # the map data rather than a trip anyone would drive. Nothing bounds the
  # distance a fee is charged on, and whether anything SHOULD is Hamma9900's
  # decision (a cap moves money off the courier unless the platform pays it).
  #
  # This decides nothing. It shows which real orders a ratio of `k` would have
  # touched, so a cap is chosen from his own orders rather than from synthetic
  # pairs. No hypothetical fee is computed: re-deriving what an order "would
  # have cost" would be a second copy of the pricing, and the one that is
  # wrong nobody would notice. The charged fee is shown as it was charged.
  #
  # Only road-priced orders: a straight-line order's ratio is 1 by definition.
  class Detours
    DEFAULT_RATIO = 3.0
    WINDOW = 30.days

    Row = Struct.new(:order, :straight_km, :road_km, :ratio, keyword_init: true)

    def initialize(ratio: DEFAULT_RATIO, since: WINDOW.ago)
      @ratio = ratio.to_f.positive? ? ratio.to_f : DEFAULT_RATIO
      @since = since
    end

    attr_reader :ratio, :since

    # The orders measured, so "4 orders" can be read against "of 212".
    def measured
      @measured ||= Order.where(created_at: @since.., distance_source: Route::OSRM)
                         .where.not(distance_km: nil)
                         .includes(:merchant)
                         .filter_map { |order| row_for(order) }
    end

    def over
      measured.select { |row| row.ratio > @ratio }.sort_by { |row| -row.ratio }
    end

    private

    def row_for(order)
      straight = Geo::Distance.km(
        from_lat: order.merchant&.latitude, from_lng: order.merchant&.longitude,
        to_lat: order.delivery_latitude, to_lng: order.delivery_longitude
      )
      # Too close to measure a ratio honestly: a few metres of snap make a
      # 50 m hop read as 10x.
      return nil if straight.nil? || straight < 0.3

      Row.new(order: order, straight_km: straight, road_km: order.distance_km.to_f,
              ratio: (order.distance_km.to_f / straight).round(2))
    end
  end
end
