class CreateCourierMoney < ActiveRecord::Migration[8.1]
  # ONE COURIER POOL, across both demand types.
  #
  # There is deliberately no `drivers` table and no `riders` table. The person
  # who fulfils a job is one human with one wallet, one credit line and one
  # commission, whether the job is a meal or a passenger. Two tables would mean
  # two balances for one person, which is how someone ends up blocked from food
  # work while holding credit for rides.
  #
  # The names here are role-neutral on purpose. The UI says "rider" in the food
  # tab and "driver" in the ride tab; the schema says courier and stays true for
  # both. This is also the economic point of the platform: food demand is spiky
  # — lunch and dinner — and a second demand stream on the same pool fills the
  # idle hours. Utilisation is what decides whether the unit economics work.
  def change
    create_table :courier_profiles do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }

      t.boolean  :is_available, null: false, default: false

      # Foreground tracking only, while a job is active. No background location.
      t.decimal  :last_latitude,  precision: 10, scale: 6
      t.decimal  :last_longitude, precision: 10, scale: 6
      t.datetime :location_updated_at

      # Which demand types this courier may be offered.
      #
      # An ARRAY, reversing an earlier decision to use one boolean per kind.
      # Two booleans were simpler to query and I preferred them — but the
      # supply side has now been broadened twice in an hour, a third demand
      # type (a person-to-person parcel) is already under discussion, and a
      # boolean-per-kind means a migration for each one. The array costs a GIN
      # index and buys immunity to that.
      #
      # Not implied by vehicle, deliberately. A car driver may want passengers
      # and not other people's dinner, and that is theirs to choose.
      t.string :accepted_job_kinds, array: true, null: false, default: [ "delivery" ]

      # Identity, because a courier carries our cash and food we have paid for.
      # An Afghan tazkira, and a father's name — two couriers called Ahmad are
      # distinguished by it.
      t.string :full_name
      t.string :father_name
      t.string :national_id_number

      t.integer :vehicle_type, null: false, default: 0
      t.string  :plate_number

      # A guarantor is the real trust mechanism here, not a credit check.
      # Someone who vouches for them and can be telephoned.
      t.string :guarantor_name
      t.string :guarantor_phone
      t.string :guarantor_relation

      t.text :work_area

      # Explicitly a human decision, with a name attached to it.
      t.integer  :verification_status, null: false, default: 0
      t.datetime :verified_at
      t.bigint   :verified_by_id
      t.text     :rejection_reason

      t.timestamps
    end

    add_index :courier_profiles, :is_available
    add_index :courier_profiles, :verification_status
    add_index :courier_profiles, :national_id_number
    add_index :courier_profiles, :accepted_job_kinds, using: :gin
    add_foreign_key :courier_profiles, :users, column: :verified_by_id

    # PREPAID, never a debt.
    #
    # Couriers deposit credit, each completed job deducts our commission, and at
    # the floor the app stops assigning work. We never chase anyone, because
    # they cannot work without credit — the same mental model as phone credit.
    #
    # This is where the two demand types converge, and why Model A generalises
    # cleanly: for food the courier advances the merchant payout and is left
    # holding our commission; for a trip they simply keep the fare and owe
    # commission from this balance. No advance to anybody, so the ride flow is
    # strictly the simpler of the two.
    create_table :courier_wallets do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }

      t.decimal :balance,     precision: 12, scale: 2, null: false, default: "0.0"
      t.decimal :credit_line, precision: 12, scale: 2, null: false, default: "0.0"
      t.string  :currency, null: false, default: "AFN"

      # Bank deposits are reconciled by this code, NOT by name. Names repeat and
      # transliterate badly — Muhammad / Mohammad / Mohammed — and a 4-digit
      # code survives a bank statement.
      t.string  :top_up_code, null: false

      t.timestamps
    end

    add_index :courier_wallets, :top_up_code, unique: true

    # Append-only ledger. balance_after is stored so a statement can be read
    # without replaying every row, and so a disagreement about the balance can
    # be located at a row rather than argued about.
    create_table :wallet_entries do |t|
      t.references :courier_wallet, null: false, foreign_key: true

      # Polymorphic over Order and Trip: a commission is owed on either.
      #
      # The trade-off is real and worth stating — a polymorphic reference cannot
      # carry a database foreign key, so an orphaned source_id becomes possible
      # where `order_id` would have been protected. It is acceptable only because
      # the ledger row is self-contained: it carries its own amount, currency and
      # balance_after, so a lost source degrades to "an entry whose job is
      # unknown" rather than to wrong money. Had the amount been derived from the
      # source, this would be the wrong design.
      t.references :source, polymorphic: true, null: true

      t.integer :kind, null: false
      t.decimal :amount,        precision: 12, scale: 2, null: false
      t.string  :currency, null: false, default: "AFN"
      t.decimal :balance_after, precision: 12, scale: 2, null: false

      # WHO recorded it. A money row with no author is unauditable.
      t.references :recorded_by, null: true, foreign_key: { to_table: :users }
      t.text :note

      t.datetime :created_at, null: false
    end

    add_index :wallet_entries, [ :courier_wallet_id, :created_at ]
    add_index :wallet_entries, :kind

    # Expected AND counted, both stored, plus the named person who counted.
    # Mismatches are normal — change floats, rounding, a note left with a
    # customer. UNEXPLAINED mismatches are theft, and you cannot tell the two
    # apart if only one number was ever written down.
    create_table :settlements do |t|
      t.references :courier, null: false, foreign_key: { to_table: :users }

      t.decimal :expected_amount, precision: 12, scale: 2, null: false
      t.decimal :counted_amount,  precision: 12, scale: 2, null: false
      t.string  :currency, null: false, default: "AFN"

      # Free text as well as an optional reference: the person counting cash in
      # Kabul may not have an account, and "who counted this" must never be null.
      t.string     :counted_by_name, null: false
      t.references :counted_by, null: true, foreign_key: { to_table: :users }

      t.datetime :period_start
      t.datetime :period_end
      t.datetime :settled_at, null: false
      t.text     :note

      t.timestamps
    end

    add_index :settlements, [ :courier_id, :settled_at ]
  end
end
