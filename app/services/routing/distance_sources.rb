module Routing
  # HOW MANY FARES WERE PRICED BY ROAD, AND HOW MANY BY STRAIGHT LINE.
  #
  # When the router is unreachable, DistanceResolver falls back to the straight
  # line, and every fare in that time is quietly 15-20% low: a discount nobody
  # authorised. Each order and trip records which it used (`distance_source`,
  # indexed), and until 25 Sept 2026 nothing counted it. This is that count, so
  # "is the router down?" has an answer on the reports page without a console.
  #
  # `unrecorded` is shown, never folded into either side: it means a row that
  # never went through a quote (seeded rows do this) or a quote with no
  # coordinates. A count that hides it would say "all road" while pricing
  # nothing.
  #
  # It decides nothing: no alarm threshold, and no repricing. Whether a fare
  # priced by straight line during an outage is repriced afterwards, or
  # accepted as lost margin, is Hamma9900's decision.
  class DistanceSources
    WINDOW = 30.days
    SOURCES = [ Route::OSRM, Route::STRAIGHT_LINE, "unrecorded" ].freeze
    KINDS = { "Deliveries" => Order, "Rides" => Trip }.freeze

    def initialize(since: WINDOW.ago.beginning_of_day, today: Time.zone.today)
      @since = since
      @today = today
    end

    attr_reader :since

    # { "Deliveries" => { window: {"osrm"=>n, ...}, today: {...} }, "Rides" => ... }
    def counts
      @counts ||= KINDS.transform_values do |model|
        { window: tally(model.where(created_at: @since..)),
          today: tally(model.where(created_at: @today.beginning_of_day..)) }
      end
    end

    def straight_line_share(kind, span = :window)
      row = counts.fetch(kind).fetch(span)
      priced = row[Route::OSRM] + row[Route::STRAIGHT_LINE]
      priced.zero? ? nil : (row[Route::STRAIGHT_LINE] * 100.0 / priced).round(1)
    end

    private

    def tally(scope)
      grouped = scope.group(:distance_source).count
      SOURCES.index_with { |source| grouped.fetch(source == "unrecorded" ? nil : source, 0) }
    end
  end
end
