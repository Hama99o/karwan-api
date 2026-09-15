module Routing
  # One routed result, in the units the rest of the app wants.
  #
  # A real `class ... < Data.define(...)` body rather than `Data.define(...) do
  # ... end`, because constants assigned inside that block are lexically scoped
  # to the ENCLOSING module — `OSRM = "osrm"` there defines `Routing::OSRM`, not
  # `Route::OSRM`, and the reference fails with an uninitialized constant. A
  # class body puts them where they are read.
  class Route < Data.define(:distance_km, :duration_minutes, :source, :geometry,
                            :origin_snap_metres, :destination_snap_metres)
    OSRM = "osrm".freeze
    STRAIGHT_LINE = "straight_line".freeze
    SOURCES = [ OSRM, STRAIGHT_LINE ].freeze

    # `source` is not decoration. A fare has to be explainable months later, and
    # "why was this ride 180 AFN" is a question that will be asked — so every
    # quote records WHICH method produced its distance. Two rides at the same
    # price computed two different ways must be distinguishable in the data.
    def osrm?
      source == OSRM
    end

    def straight_line?
      source == STRAIGHT_LINE
    end

    # Above this the pin is not on the road network at all — Kabul is full of
    # walled compounds, and the measured worst case was a pin inside the
    # airport perimeter, 357 m from any mapped road. When this trips, the
    # landmark voice note and the phone number are doing the real work, which
    # is already the design. It is recorded, never "fixed" by moving the pin:
    # the pin is what the customer said, the snap is what the router needed.
    def pin_far_from_road?
      threshold = Setting.fetch("routing_snap_warning_metres")

      [ origin_snap_metres, destination_snap_metres ].compact.any? { |metres| metres > threshold }
    end
  end
end
