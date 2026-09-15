class AddMerchantCategoriesAndSearch < ActiveRecord::Migration[8.1]
  # Two different things were being conflated, so both are spelled out here:
  #
  #   catalog_categories — a RESTAURANT'S OWN menu structure ("Starters", "Kebab",
  #     "Drinks"), typed by the merchant, in its own language, in its own
  #     order. Per merchant. Not comparable across merchants.
  #
  #   merchant_categories        — a GLOBAL, SEEDED taxonomy ("Kabab", "Mantu", "Pizza",
  #     "Burger", "Afghan", "Fast food") used to browse and filter ACROSS
  #     merchants. This is what "best category" means and it did not exist.
  #
  # Names are per-locale columns rather than a translations table, matching how
  # hatiwal-api handles category names. Three locales is not enough to earn the
  # indirection, and a missing column is a visible blank rather than a silent
  # fallback to the wrong language.
  def change
    create_table :merchant_categories do |t|
      t.string  :slug, null: false
      t.string  :name_en, null: false
      t.string  :name_fa, null: false
      t.string  :name_ps, null: false
      t.integer :position, null: false, default: 0
      t.boolean :is_active, null: false, default: true

      t.timestamps
    end

    add_index :merchant_categories, :slug, unique: true
    add_index :merchant_categories, [ :is_active, :position ]

    create_table :merchant_category_assignments do |t|
      t.references :merchant, null: false, foreign_key: true
      t.references :merchant_category, null: false, foreign_key: true

      t.timestamps
    end

    add_index :merchant_category_assignments, [ :merchant_id, :merchant_category_id ], unique: true

    # Trigram matching, for the reason that matters in this market: "kabab",
    # "kebab" and "kabob" are the same food, Pashto and Dari transliterate into
    # Latin differently per person, and nobody spells "Shar-e-Naw" the same way
    # twice. English stemming (tsvector) does nothing for any of that;
    # similarity does.
    enable_extension "pg_trgm" unless extension_enabled?("pg_trgm")

    add_index :merchants, :name, using: :gin, opclass: :gin_trgm_ops,
                                   name: "index_merchants_on_name_trgm"
    add_index :catalog_items, :name, using: :gin, opclass: :gin_trgm_ops,
                                  name: "index_catalog_items_on_name_trgm"
    add_index :merchant_categories, :name_en, using: :gin, opclass: :gin_trgm_ops,
                                   name: "index_merchant_categories_on_name_en_trgm"
  end
end
