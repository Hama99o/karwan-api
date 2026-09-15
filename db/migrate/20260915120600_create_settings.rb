class CreateSettings < ActiveRecord::Migration[8.1]
  def change
    # Config as ROWS, not constants. Commission %, delivery fee, rider fee,
    # cash-in-hand limit, default credit line, ETA average speed — all tuned
    # weekly. Hard-coding them means a deploy every time the owner changes his
    # mind about a number, and he will.
    create_table :settings do |t|
      t.string     :key, null: false
      t.string     :value
      # Without this, every reader guesses. A setting read as a String where the
      # writer meant a Decimal is how "0.125" becomes zero.
      t.integer    :value_type, null: false, default: 0
      # Only for money-typed settings. Never sum across currencies.
      t.string     :currency
      t.text       :description
      t.references :updated_by, null: true, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :settings, :key, unique: true
  end
end
