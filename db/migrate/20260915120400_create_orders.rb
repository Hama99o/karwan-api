class CreateOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :orders do |t|
      # Human-readable, because support is a person on a phone asking "what is
      # your order number?" and nobody reads out a bigint.
      t.string     :code, null: false

      t.references :customer,   null: false, foreign_key: { to_table: :users }
      t.references :merchant, null: false, foreign_key: true
      # One courier pool across both demand types. The column is role-neutral
      # because the same human fulfils a food order and a trip, with one wallet
      # and one commission; the UI says "rider" in the food tab and "driver" in
      # the ride tab.
      t.references :courier,    null: true,  foreign_key: { to_table: :users }

      # ---- Money -------------------------------------------------------------
      # Model A, worked example: food 400, delivery_fee 100, commission 50.
      #   customer_total    = 500  (items_total + delivery_fee)
      #   merchant_payout = 350  (items_total - commission) — rider advances it
      #   courier_fee       = 100  (the courier keeps it)
      # After delivery the courier is holding our 50. That is the entire exposure.
      #
      # Every one of these is a SNAPSHOT. commission_rate and the fee settings
      # are tuned weekly; an order must always render the numbers it was placed
      # with, so nothing here is recomputed from live config afterwards.
      #
      # delivery_fee and courier_fee are separate columns even though v0 sets them
      # equal, because they are separate config rows and the moment the platform
      # takes a cut of delivery they diverge.
      t.decimal :items_total,        precision: 12, scale: 2, null: false, default: "0.0"
      t.decimal :delivery_fee,      precision: 12, scale: 2, null: false, default: "0.0"
      t.decimal :commission,        precision: 12, scale: 2, null: false, default: "0.0"
      t.decimal :courier_fee,       precision: 12, scale: 2, null: false, default: "0.0"
      t.decimal :merchant_payout, precision: 12, scale: 2, null: false, default: "0.0"
      t.decimal :customer_total,    precision: 12, scale: 2, null: false, default: "0.0"
      t.string  :currency, null: false, default: "AFN"

      t.integer :payment_method, null: false, default: 0

      # ---- State -------------------------------------------------------------
      t.integer :status, null: false, default: 0

      # payment_status is an EXPLICIT column, never derived. "Has this money
      # reached me?" is asked a thousand times a day and must be answerable
      # with a WHERE, not a join across settlements.
      #
      # Named for payment rather than cash deliberately, though cash is the only
      # method in v0. The same three states carry either model —
      # pending -> collected -> settled for cash, pending -> paid -> settled for
      # digital — so online payment later needs no second mechanism and no code
      # deciding which column to trust. Adding an enum value to an integer
      # column needs no migration at all; renaming the column would have.
      t.integer :payment_status, null: false, default: 0

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
      t.datetime :merchant_paid_at
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
    add_index :orders, :payment_status
    add_index :orders, :created_at
    add_index :orders, [ :status, :created_at ]
    add_index :orders, [ :merchant_id, :status ]
    # This one IS the "has the money reached me" query. Keep it.
    add_index :orders, [ :courier_id, :payment_status ]

    # Snapshot of name, price and options AT ORDER TIME. Never join live to
    # catalog_items for a historical order — menus change daily.
    create_table :order_items do |t|
      t.references :order, null: false, foreign_key: true
      # Reference only, and nullable: the menu item may be renamed or deleted.
      # Nothing user-facing reads through it.
      t.references :catalog_item, null: true, foreign_key: true

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
  end
end
