class CreateMerchants < ActiveRecord::Migration[8.1]
  def change
    # A GROWABLE taxonomy, not an enum and not a check constraint.
    #
    # The supply side has been broadened twice in one hour — restaurant, then
    # "restaurant or store", then "for example send books etc". An enum would
    # mean a migration for the first bookshop. A table means a row.
    #
    # Seeded by us, not merchant-editable, and translated, because the customer
    # app renders these as browse labels in three locales.
    create_table :merchant_kinds do |t|
      t.string  :slug, null: false
      t.string  :name_en, null: false
      t.string  :name_fa, null: false
      t.string  :name_ps, null: false
      t.integer :position, null: false, default: 0
      t.boolean :is_active, null: false, default: true

      t.timestamps
    end

    add_index :merchant_kinds, :slug, unique: true
    add_index :merchant_kinds, [ :is_active, :position ]

    create_table :merchants do |t|
      # Nullable: admin onboards merchants in v0, so a merchant exists
      # before its owner has an account. Merchants are not self-serve.
      t.references :owner, null: true, foreign_key: { to_table: :users }

      t.string  :name, null: false
      t.string  :phone, null: false
      t.text    :description

      # What kind of business this is. The reason the table is `merchants` and
      # not `restaurants`. Everything downstream — orders, catalog, dispatch,
      # the courier pool — is identical across kinds; only the vocabulary in the
      # UI changes ("menu" for a kitchen, "products" for a shop).
      t.references :merchant_kind, null: false, foreign_key: true

      # The single most important control in the whole system. A merchant
      # marked open that isn't is the most damaging state there is, so it
      # defaults to CLOSED and is only ever opened deliberately.
      t.boolean :is_open, null: false, default: false

      # NULLABLE, and deliberately not defaulted. A book has no preparation
      # time; a plate of kabab does. Defaulting it to 20 would put a meaningless
      # number on every bookshop, and someone would eventually believe it.
      t.integer :prep_time_minutes

      t.decimal :latitude,  precision: 10, scale: 6
      t.decimal :longitude, precision: 10, scale: 6
      t.text    :landmark_note

      # Per-merchant override of the global commission setting. 0.1250 is the
      # brief's worked example: 50 AFN on 400 AFN of food.
      t.decimal :commission_rate, precision: 5, scale: 4, null: false, default: "0.125"

      t.integer :status, null: false, default: 0

      t.timestamps
    end

    add_index :merchants, :status
    add_index :merchants, :is_open
    add_index :merchants, :name

    # day_of_week uses Ruby's Time#wday — 0 = Sunday — NOT the Afghan week,
    # which starts Saturday. The display order is the client's problem; storing
    # anything but wday means converting on every comparison.
    create_table :merchant_opening_hours do |t|
      t.references :merchant, null: false, foreign_key: true
      t.integer    :day_of_week, null: false
      t.time       :opens_at, null: false
      t.time       :closes_at, null: false

      t.timestamps
    end

    add_index :merchant_opening_hours, [ :merchant_id, :day_of_week ]
  end
end
