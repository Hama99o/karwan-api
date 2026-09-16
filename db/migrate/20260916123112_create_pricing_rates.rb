# RATES THAT VARY BY VEHICLE, which a key-value `Setting` cannot hold.
#
# The rule that keeps the two config mechanisms from becoming a mess, and it is
# statable so the next person knows where to look:
#
#   **`Setting` holds scalars. `pricing_rates` holds anything that varies by
#   vehicle.**
#
# Hamma9900 wants the calculation to depend on the vehicle — bike, rishka,
# zarang — and 2 demand types × 6 vehicles × 4 fields is 48 `Setting` rows,
# which is a combinatorial mess in a key-value table.
#
# ── THE ASYMMETRY BETWEEN THE TWO DEMAND TYPES IS THE POINT ────────────────
#
# It is expressed in ROWS here rather than in a comment somewhere, because the
# next person to touch pricing will otherwise assume symmetry and there is
# none:
#
#   ride / customer / <class>   — THE PASSENGER PICKS THE CLASS and sees that
#                                 class's price. A motorbike ride is much
#                                 cheaper than a car, and the passenger is the
#                                 right person to decide whether they want
#                                 cheap or comfortable. The quote stays upfront
#                                 and frozen (correction 13) precisely BECAUSE
#                                 the class is chosen before the quote — which
#                                 is what resolves "the fare depends on the
#                                 vehicle" against "the fare is quoted upfront".
#
#   delivery / courier / <class> — the customer does not choose and should not
#                                 care: food arrives, and how it arrived is our
#                                 problem. One customer-facing fee, with the
#                                 vehicle affecting what the COURIER EARNS. A
#                                 bicycle on a 6 km run is worth a different fee
#                                 to us than a motorbike; that is a
#                                 courier-economics lever, not a pricing lever.
#
#   delivery / customer          — stays in `Setting`, because it genuinely is a
#                                 scalar: one fee per distance, no vehicle
#                                 dimension. Hamma9900 tunes those keys weekly
#                                 already.
#
# `vehicle_type` is nullable for a rate that applies to any vehicle, which is
# what an "all classes" row means.
class CreatePricingRates < ActiveRecord::Migration[8.1]
  def change
    create_table :pricing_rates do |t|
      t.string  :job_kind, null: false
      t.integer :audience, null: false
      t.integer :vehicle_type

      # A two-part tariff plus a floor, the same shape for both demand types —
      # `per_minute` is simply 0 where it does not apply, rather than a
      # different formula per row.
      t.decimal :base,       precision: 12, scale: 2, null: false, default: "0.0"
      t.decimal :per_km,     precision: 12, scale: 2, null: false, default: "0.0"
      t.decimal :per_minute, precision: 12, scale: 2, null: false, default: "0.0"
      # The floor is what makes a 200-metre job worth taking at all.
      t.decimal :minimum,    precision: 12, scale: 2, null: false, default: "0.0"
      # On every amount, from the first migration (one-way door #2).
      t.string  :currency, null: false, default: "AFN"

      # Whether a PASSENGER may choose this class. Meaningless for a courier
      # row, and false for `on_foot` — nobody hails a pedestrian.
      t.boolean :is_selectable, null: false, default: false
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    # One rate per audience per vehicle per demand type. A duplicate would mean
    # two prices for the same ride and code deciding which to trust.
    add_index :pricing_rates, %i[job_kind audience vehicle_type], unique: true
  end
end
