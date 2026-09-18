module Geo
  # Is this coordinate somewhere we can actually answer about?
  #
  # ── Why this is NARROWER than the map's bounds ───────────────────────────
  #
  # `hatiwal-map/build-styles.mjs:454` sets the tileset to
  # `[44.0, 23.6, 77.9, 39.8]` — AF + PK + IR, matching planetiler's `--bounds`
  # exactly. That is the area the map can DRAW, deliberately wider than
  # Afghanistan so the country does not sit against a blank edge.
  #
  # The ROUTER is a different question. Its graph is built from
  # `afghanistan-latest.osm.pbf`, so a pin in Peshawar is inside the tileset and
  # outside the road network: OSRM would either snap it to the nearest Afghan
  # road hundreds of kilometres away or return no route at all. Both are worse
  # than saying "we do not cover that".
  #
  # So these are the extract's bounds, not the tileset's, and the two must NOT
  # be unified — that is the trap `hatiwal-map`'s runbook already records in the
  # other direction (bounds that disagree make MapLibre request tiles that do
  # not exist).
  module Bounds
    # Afghanistan, with a little padding: Herat/Iran in the west, the Wakhan
    # corridor in the east, Nimruz in the south, the Amu Darya in the north.
    #
    # A RECTANGLE, AND IT IS HONEST ABOUT WHAT THAT MEANS. The eastern tip
    # reaches 74.9°E in the Wakhan, so any box round Afghanistan also contains
    # Peshawar (71.5°E) and a strip of Pakistan and Iran. This is a **cost
    # bound**, not a border: it stops a signed-in client routing across
    # continents on Hamma9900's CPU. Pins just over the border still reach the
    # router and get whatever the Afghanistan graph can answer — which is the
    # same degradation `pin_far_from_road?` already reports. A real border needs
    # a polygon, and nothing yet justifies carrying one.
    MIN_LNG = 60.4
    MAX_LNG = 74.9
    MIN_LAT = 29.3
    MAX_LAT = 38.5

    def self.contains?(lat:, lng:)
      return false if lat.blank? || lng.blank?

      lat = lat.to_d
      lng = lng.to_d

      lat.between?(MIN_LAT, MAX_LAT) && lng.between?(MIN_LNG, MAX_LNG)
    rescue ArgumentError
      # A non-numeric coordinate is out of bounds rather than an exception: this
      # is reached from a public-facing proxy and "0" is not a valid answer.
      false
    end
  end
end
