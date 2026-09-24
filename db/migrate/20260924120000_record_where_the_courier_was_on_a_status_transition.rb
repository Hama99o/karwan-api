class RecordWhereTheCourierWasOnAStatusTransition < ActiveRecord::Migration[8.1]
  # ── THE ONLY EVIDENCE WHEN A CUSTOMER SAYS THE FOOD NEVER ARRIVED ─────────
  #
  # `REALTIME_AND_SCALE.md` §4 and `REQUIREMENTS.md` R15 both name this gap:
  # *"Position at the moments that get disputed. Where the courier was when
  # they marked picked up and delivered. Cheap to store, and it is the only
  # evidence when a customer says the food never arrived. Recommended; not
  # built."*
  #
  # `courier_profiles` keeps ONE position per courier, overwritten in place by
  # design — history is deliberately not kept there. So the position at the
  # moment of "delivered" survives only until the next fix, a few seconds. It
  # is exactly the one-way-door shape: what is not written at the moment
  # cannot be reconstructed.
  #
  # ON THE TRANSITION ROW, not two columns per job table: every courier move —
  # picked up, delivered, arrived, failed at the door — already writes one
  # append-only row here for both demand types. "Nobody home" is the most
  # disputed moment of all, and a per-job pair of columns would have missed it.
  #
  # `courier_located_at` is the FIX's time, not the transition's. A position
  # without its age reads as "he was here" when it may mean "he was here four
  # minutes earlier"; with it, the gap is on the row and nobody has to guess.
  #
  # ADDITIVE AND NULLABLE. Existing rows keep nil, which is the truth: the
  # position was never captured and cannot be invented now.
  def change
    change_table :status_transitions, bulk: true do |t|
      t.decimal :courier_latitude, precision: 10, scale: 6
      t.decimal :courier_longitude, precision: 10, scale: 6
      t.datetime :courier_located_at
    end
  end
end
