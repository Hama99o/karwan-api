class AddRoutingToJobs < ActiveRecord::Migration[8.1]
  # What justified the fare, recorded at the moment it was quoted.
  #
  # One-way door #4 in spirit: what is not recorded when it happens cannot be
  # reconstructed. A fare has to be explainable months later — "why was this
  # ride 180 AFN" is a question that will be asked — and two jobs at the same
  # price computed two different ways must be distinguishable in the data.
  #
  # `orders` gains distance and duration at all, which it did not store: the
  # ETA quoted to the customer was computed, shown, and then thrown away.
  def change
    change_table :orders, bulk: true do |t|
      t.decimal :distance_km, precision: 8, scale: 3
      t.integer :duration_minutes
      t.string  :distance_source
      # The drawn line. ~4 KB of GeoJSON for a 5.7 km Kabul route, stored
      # rather than re-fetched because the courier app must draw the SAME route
      # the fare was based on — a later request could return a different one.
      t.jsonb   :route_geometry
      # How far OSRM had to move each pin to reach a road. Measured 21.9 m to
      # 357.2 m on real Kabul points, the worst being a pin inside the airport
      # perimeter. When a courier says "the app sent me to the wrong gate",
      # this is the answer.
      t.decimal :origin_snap_metres, precision: 8, scale: 1
      t.decimal :destination_snap_metres, precision: 8, scale: 1
    end

    change_table :trips, bulk: true do |t|
      t.string  :distance_source
      t.jsonb   :route_geometry
      t.decimal :origin_snap_metres, precision: 8, scale: 1
      t.decimal :destination_snap_metres, precision: 8, scale: 1
    end

    # So "how many fares were routed vs straight-lined" is one indexed count
    # rather than a table scan, which is the question to ask after switching
    # the setting on.
    add_index :orders, :distance_source
    add_index :trips, :distance_source
  end
end
