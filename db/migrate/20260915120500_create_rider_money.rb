class CreateRiderMoney < ActiveRecord::Migration[8.1]
  def change
    # Operational rider state, kept OUT of rider_wallets so the money table
    # stays money-only, and out of users so users stays role-agnostic.
    create_table :rider_profiles do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }

      t.boolean  :is_available, null: false, default: false

      # Foreground tracking only, while an order is active. No background
      # location in v0.
      t.decimal  :last_latitude,  precision: 10, scale: 6
      t.decimal  :last_longitude, precision: 10, scale: 6
      t.datetime :location_updated_at

      t.timestamps
    end

    add_index :rider_profiles, :is_available

    # PREPAID, never a debt. Riders deposit credit; each delivered order
    # deducts the commission; at zero the app stops assigning orders. We never
    # chase anyone because they cannot work without credit — the same mental
    # model as phone credit.
    create_table :rider_wallets do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }

      t.decimal :balance,     precision: 12, scale: 2, null: false, default: "0.0"
      # A new rider starts with a small negative allowance so they can work
      # with nothing, and so a reconciliation delay never blocks them. Raised
      # with track record — that is what makes it a reason to stay.
      t.decimal :credit_line, precision: 12, scale: 2, null: false, default: "0.0"
      t.string  :currency, null: false, default: "AFN"

      # Bank deposits are reconciled by this code, NOT by name. Names repeat and
      # transliterate badly — Muhammad / Mohammad / Mohammed — and a 4-digit
      # code survives a bank statement.
      t.string  :top_up_code, null: false

      t.timestamps
    end

    add_index :rider_wallets, :top_up_code, unique: true

    # Append-only ledger. balance_after is stored so a statement can be read
    # back without replaying every row, and so a disagreement about the balance
    # can be located at a row rather than argued about.
    create_table :wallet_entries do |t|
      t.references :rider_wallet, null: false, foreign_key: true
      t.references :order, null: true, foreign_key: true

      t.integer :kind, null: false
      t.decimal :amount,        precision: 12, scale: 2, null: false
      t.string  :currency, null: false, default: "AFN"
      t.decimal :balance_after, precision: 12, scale: 2, null: false

      # WHO recorded it. A money row with no author is unauditable.
      t.references :recorded_by, null: true, foreign_key: { to_table: :users }
      t.text :note

      t.datetime :created_at, null: false
    end

    add_index :wallet_entries, [ :rider_wallet_id, :created_at ]
    add_index :wallet_entries, :kind

    # Expected AND counted, both stored, plus the named person who counted.
    # Mismatches are normal; unexplained mismatches are theft. Storing only one
    # number makes the difference unrecoverable.
    create_table :settlements do |t|
      t.references :rider, null: false, foreign_key: { to_table: :users }

      t.decimal :expected_amount, precision: 12, scale: 2, null: false
      t.decimal :counted_amount,  precision: 12, scale: 2, null: false
      t.string  :currency, null: false, default: "AFN"

      # Free text, not just a user reference: the person who counted the cash in
      # Kabul may not have an account, and "who counted this" must never be null.
      t.string     :counted_by_name, null: false
      t.references :counted_by, null: true, foreign_key: { to_table: :users }

      t.datetime :period_start
      t.datetime :period_end
      t.datetime :settled_at, null: false
      t.text     :note

      t.timestamps
    end

    add_index :settlements, [ :rider_id, :settled_at ]
  end
end
