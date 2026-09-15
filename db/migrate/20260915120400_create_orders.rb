class CreateOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :orders do |t|
      # Human-readable, because support is a person on a phone asking "what is
      # your order number?" and nobody reads out a bigint.
      t.string     :code, null: false

      t.references :customer,   null: false, foreign_key: { to_table: :users }
      t.references :restaurant, null: false, foreign_key: true
      t.references :rider,      null: true,  foreign_key: { to_table: :users }

      # ---- Money -------------------------------------------------------------
      # Model A, worked example: food 400, delivery_fee 100, commission 50.
      #   customer_total    = 500  (food_total + delivery_fee)
      #   restaurant_payout = 350  (food_total - commission) — rider advances it
      #   rider_fee         = 100  (rider keeps it)
      # After delivery the rider is holding our 50. That is the entire exposure.
      #
      # Every one of these is a SNAPSHOT. commission_rate and the fee settings
      # are tuned weekly; an order must always render the numbers it was placed
      # with, so nothing here is recomputed from live config afterwards.
      #
      # delivery_fee and rider_fee are separate columns even though v0 sets them
      # equal, because they are separate config rows and the moment the platform
      # takes a cut of delivery they diverge.
      t.decimal :food_total,        precision: 12, scale: 2, null: false, default: "0.0"
      t.decimal :delivery_fee,      precision: 12, scale: 2, null: false, default: "0.0"
      t.decimal :commission,        precision: 12, scale: 2, null: false, default: "0.0"
      t.decimal :rider_fee,         precision: 12, scale: 2, null: false, default: "0.0"
      t.decimal :restaurant_payout, precision: 12, scale: 2, null: false, default: "0.0"
      t.decimal :customer_total,    precision: 12, scale: 2, null: false, default: "0.0"
      t.string  :currency, null: false, default: "AFN"

      t.integer :payment_method, null: false, default: 0

      # ---- State -------------------------------------------------------------
      t.integer :status, null: false, default: 0

      # cash_status is an EXPLICIT column, never derived. "Has this money
      # reached me?" is asked a thousand times a day and must be answerable
      # with a WHERE, not a join across settlements.
      t.integer :cash_status, null: false, default: 0

      # ---- Delivery address SNAPSHOT ----------------------------------------
      # Never joined to `addresses`: the customer edits and deletes those, and a
      # historical order must still show where it actually went. Same reason
      # order_items snapshot their prices.
      t.decimal :delivery_latitude,  precision: 10, scale: 6, null: false
      t.decimal :delivery_longitude, precision: 10, scale: 6, null: false
      t.text    :delivery_landmark_note
      t.string  :customer_phone, null: false
      t.text    :notes

      # ---- One timestamp per transition -------------------------------------
      t.datetime :placed_at
      t.datetime :accepted_at
      t.datetime :rejected_at
      t.datetime :preparing_at
      t.datetime :ready_at
      t.datetime :picked_up_at
      t.datetime :restaurant_paid_at
      t.datetime :delivered_at
      t.datetime :cancelled_at
      t.datetime :failed_at
      t.datetime :settled_at

      t.integer :rejection_reason
      t.integer :cancellation_reason
      t.integer :cancelled_by_role
      t.integer :failure_reason

      t.timestamps
    end

    add_index :orders, :code, unique: true
    add_index :orders, :status
    add_index :orders, :cash_status
    add_index :orders, :created_at
    add_index :orders, [ :status, :created_at ]
    add_index :orders, [ :restaurant_id, :status ]
    # This one IS the "has the money reached me" query. Keep it.
    add_index :orders, [ :rider_id, :cash_status ]

    # Snapshot of name, price and options AT ORDER TIME. Never join live to
    # menu_items for a historical order — menus change daily.
    create_table :order_items do |t|
      t.references :order, null: false, foreign_key: true
      # Reference only, and nullable: the menu item may be renamed or deleted.
      # Nothing user-facing reads through it.
      t.references :menu_item, null: true, foreign_key: true

      t.string  :name, null: false
      t.decimal :unit_price,    precision: 12, scale: 2, null: false
      t.decimal :options_total, precision: 12, scale: 2, null: false, default: "0.0"
      t.integer :quantity, null: false, default: 1
      t.decimal :line_total,    precision: 12, scale: 2, null: false
      t.string  :currency, null: false, default: "AFN"
      t.text    :notes

      t.timestamps
    end

    create_table :order_item_options do |t|
      t.references :order_item, null: false, foreign_key: true
      t.string     :option_name, null: false
      t.string     :value_name, null: false
      t.decimal    :price_delta, precision: 12, scale: 2, null: false, default: "0.0"
      t.string     :currency, null: false, default: "AFN"

      t.timestamps
    end

    # Every state change records WHO moved it and WHEN. An order stuck with no
    # timeout is a person waiting with cold food; this table is how you find
    # them, and how you answer "who cancelled this?".
    #
    # Append-only, so no updated_at.
    create_table :order_status_transitions do |t|
      t.references :order, null: false, foreign_key: true
      t.integer    :from_status
      t.integer    :to_status, null: false
      # Nullable actor = the system did it, i.e. a timeout fired.
      t.references :actor, null: true, foreign_key: { to_table: :users }
      t.integer    :actor_role
      t.text       :reason

      t.datetime   :created_at, null: false
    end

    add_index :order_status_transitions, [ :order_id, :created_at ]

    # Dispatch, kept crude on purpose: offer to the nearest available rider
    # whose wallet can fund the food, time out, offer to the next, then surface
    # to admin. No batching, no optimisation, no zones.
    create_table :order_offers do |t|
      t.references :order, null: false, foreign_key: true
      t.references :rider, null: false, foreign_key: { to_table: :users }

      t.integer  :status, null: false, default: 0
      t.integer  :sequence, null: false, default: 1
      t.datetime :offered_at, null: false
      # Every offer has a deadline. An offer with no timeout is how an order
      # sits unassigned while a rider who went home never declines it.
      t.datetime :expires_at, null: false
      t.datetime :responded_at

      t.timestamps
    end

    add_index :order_offers, [ :order_id, :sequence ], unique: true
    add_index :order_offers, [ :rider_id, :status ]
    add_index :order_offers, :expires_at
  end
end
