class AddCuisinesAndSearch < ActiveRecord::Migration[8.1]
  # Two different things were being conflated, so both are spelled out here:
  #
  #   menu_categories — a RESTAURANT'S OWN menu structure ("Starters", "Kebab",
  #     "Drinks"), typed by the restaurant, in its own language, in its own
  #     order. Per restaurant. Not comparable across restaurants.
  #
  #   cuisines        — a GLOBAL, SEEDED taxonomy ("Kabab", "Mantu", "Pizza",
  #     "Burger", "Afghan", "Fast food") used to browse and filter ACROSS
  #     restaurants. This is what "best category" means and it did not exist.
  #
  # Names are per-locale columns rather than a translations table, matching how
  # hatiwal-api handles category names. Three locales is not enough to earn the
  # indirection, and a missing column is a visible blank rather than a silent
  # fallback to the wrong language.
  def change
    create_table :cuisines do |t|
      t.string  :slug, null: false
      t.string  :name_en, null: false
      t.string  :name_fa, null: false
      t.string  :name_ps, null: false
      t.integer :position, null: false, default: 0
      t.boolean :is_active, null: false, default: true

      t.timestamps
    end

    add_index :cuisines, :slug, unique: true
    add_index :cuisines, [ :is_active, :position ]

    create_table :restaurant_cuisines do |t|
      t.references :restaurant, null: false, foreign_key: true
      t.references :cuisine, null: false, foreign_key: true

      t.timestamps
    end

    add_index :restaurant_cuisines, [ :restaurant_id, :cuisine_id ], unique: true

    # Trigram matching, for the reason that matters in this market: "kabab",
    # "kebab" and "kabob" are the same food, Pashto and Dari transliterate into
    # Latin differently per person, and nobody spells "Shar-e-Naw" the same way
    # twice. English stemming (tsvector) does nothing for any of that;
    # similarity does.
    enable_extension "pg_trgm" unless extension_enabled?("pg_trgm")

    add_index :restaurants, :name, using: :gin, opclass: :gin_trgm_ops,
                                   name: "index_restaurants_on_name_trgm"
    add_index :menu_items, :name, using: :gin, opclass: :gin_trgm_ops,
                                  name: "index_menu_items_on_name_trgm"
    add_index :cuisines, :name_en, using: :gin, opclass: :gin_trgm_ops,
                                   name: "index_cuisines_on_name_en_trgm"
  end
end
