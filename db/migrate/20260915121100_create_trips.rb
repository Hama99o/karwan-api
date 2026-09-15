class CreateTrips < ActiveRecord::Migration[8.1]
  # The second demand type: a passenger, two pins, a fare.
  #
  # SCHEMA ONLY. There is deliberately no trip UI, no fare calculator and no
  # routing engine behind this. The table exists now, while there are ten
  # commits and no data, so that adding rides later is a calculator and some
  # screens rather than a restructure of everything that references an order.
  #
  # `trips` is a SEPARATE table from `orders` on purpose. Food has line items,
  # options, a merchant, a prep time and one destination; a ride has two pins,
  # no items and no third party. Forcing one table to serve both would mean a
  # dozen columns that are always null for half the rows, and a status enum
  # where half the values are meaningless. What they genuinely share — the
  # courier, the wallet, the commission, dispatch and the transition log — is
  # shared through polymorphism instead.
  def change
    create_table :trips do |t|
      t.string     :code, null: false
      t.references :passenger, null: false, foreign_key: { to_table: :users }
      t.references :courier, null: true, foreign_key: { to_table: :users }

      # ---- Two pins, not addresses ------------------------------------------
      # Same reasoning as delivery: Afghan addresses are unreliable and people
      # navigate by landmarks. Snapshotted, so a past trip still says where it
      # actually went.
      t.decimal :pickup_latitude,  precision: 10, scale: 6, null: false
      t.decimal :pickup_longitude, precision: 10, scale: 6, null: false
      t.text    :pickup_landmark_note
      t.decimal :dropoff_latitude,  precision: 10, scale: 6, null: false
      t.decimal :dropoff_longitude, precision: 10, scale: 6, null: false
      t.text    :dropoff_landmark_note

      t.string :passenger_phone, null: false
      t.text   :notes

      # Straight-line distance and the ETA speed setting, NOT a routed path.
      # Same approach as delivery ETA: no OSRM in v0. Stored because the fare
      # was quoted from them and must stay explainable afterwards.
      t.decimal :distance_km, precision: 8, scale: 3
      t.integer :duration_minutes

      # ---- Money -------------------------------------------------------------
      # Model A generalises, and the ride flow is the SIMPLER half: the courier
      # collects the fare, keeps it, and owes commission from their prepaid
      # wallet. There is no advance to anybody, no merchant payout, and
      # nothing for us to reimburse if a passenger refuses to pay beyond the
      # fare itself.
      #
      # All snapshots, like orders: the fare settings get tuned weekly and a
      # past trip must render the numbers it was quoted with.
      t.decimal :fare,             precision: 12, scale: 2, null: false, default: "0.0"
      t.decimal :commission,       precision: 12, scale: 2, null: false, default: "0.0"
      t.decimal :courier_earnings, precision: 12, scale: 2, null: false, default: "0.0"
      t.string  :currency, null: false, default: "AFN"

      t.integer :payment_method, null: false, default: 0
      t.integer :status, null: false, default: 0
      # Explicit, never derived — same as orders, and named for payment rather
      # than cash so the digital path reuses it instead of adding a parallel
      # mechanism.
      t.integer :payment_status, null: false, default: 0

      t.datetime :requested_at
      t.datetime :accepted_at
      t.datetime :arrived_at
      # Named for the STATUS, not for the event. `Dispatchable#state_entered_at`
      # resolves "#{status}_at", so a column called `started_at` for a state
      # called `in_progress` silently falls back to `updated_at` — which is
      # touched on every save, so the state clock resets constantly and the
      # timeout can never fire. One-way door #3 says a timestamp per transition;
      # this is what makes it actually work.
      t.datetime :in_progress_at
      t.datetime :completed_at
      t.datetime :cancelled_at
      t.datetime :failed_at
      t.datetime :settled_at

      t.integer :cancellation_reason
      t.integer :cancelled_by_role
      t.integer :failure_reason

      t.timestamps
    end

    add_index :trips, :code, unique: true
    add_index :trips, :status
    add_index :trips, :payment_status
    add_index :trips, :created_at
    add_index :trips, [ :status, :created_at ]
    # The "has the money reached me" query, per courier, for rides.
    add_index :trips, [ :courier_id, :payment_status ]
  end
end
