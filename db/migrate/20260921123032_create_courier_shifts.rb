# WHEN A COURIER WAS AVAILABLE — the half of utilisation that cannot be counted
# after the fact.
#
# `PRODUCT.md` calls orders per rider per day "the number that decides the
# business". `/admin/reports` can only divide by couriers who COMPLETED a job,
# so a courier who was online all day and took nothing is invisible and the
# figure **flatters the business** — the wrong direction for a hiring decision.
#
# `courier_profiles.is_available` is a switch with no history, so the honest
# denominator was not merely unbuilt, it was **unrecoverable**: every day
# without this table is a day whose idle capacity can never be known.
# `CLAUDE.md`'s one-way-door doctrine is exactly this — *what you fail to
# record cannot be reconstructed* — which is why this is worth a migration now
# rather than when somebody asks for the report.
#
# `ended_at` NULL means still on shift. Nullable rather than defaulted, because
# "open" and "ended at the epoch" must not be the same value.
class CreateCourierShifts < ActiveRecord::Migration[8.1]
  def change
    create_table :courier_shifts do |t|
      t.references :courier, null: false, foreign_key: { to_table: :users }
      t.datetime :started_at, null: false
      t.datetime :ended_at

      t.timestamps
    end

    # The report asks "who was available during this window", so the index is
    # on the courier and when the shift began.
    add_index :courier_shifts, [ :courier_id, :started_at ]

    # Finding a courier's OPEN shift is the hot path — it happens on every
    # toggle — so it gets a partial index over just the open ones.
    add_index :courier_shifts, :courier_id, where: "ended_at IS NULL",
                                            name: "index_courier_shifts_open"
  end
end
