class CreateCatalog < ActiveRecord::Migration[8.1]
  def change
    create_table :catalog_categories do |t|
      t.references :merchant, null: false, foreign_key: true
      t.string     :name, null: false
      t.integer    :position, null: false, default: 0

      t.timestamps
    end

    add_index :catalog_categories, [ :merchant_id, :position ]

    create_table :catalog_items do |t|
      # merchant_id is denormalised from catalog_category. It is what every
      # policy_scope and sold-out query filters on, and going through the
      # category for it on every request buys nothing.
      t.references :merchant,    null: false, foreign_key: true
      t.references :catalog_category, null: false, foreign_key: true

      t.string  :name, null: false
      t.text    :description
      t.decimal :price, precision: 12, scale: 2, null: false
      t.string  :currency, null: false, default: "AFN"

      # The sold-out toggle. Used mid-rush, so it must be one tap from the
      # order board — which means one column, not a join.
      t.boolean :is_available, null: false, default: true

      # Nullable: falls back to the merchant's prep_time_minutes.
      t.integer :prep_time_minutes
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :catalog_items, [ :catalog_category_id, :position ]
    add_index :catalog_items, [ :merchant_id, :is_available ]

    # Options are bigger than they look: size, extras, price deltas. Modelled
    # properly now because retrofitting variants onto a flat menu is painful.
    #
    # Deliberately ONE level deep — an option value has no children. This is a
    # menu, not a configurator; nesting is how this table becomes a product
    # catalogue nobody asked for.
    create_table :catalog_item_options do |t|
      t.references :catalog_item, null: false, foreign_key: true
      t.string     :name, null: false
      t.integer    :selection_type, null: false, default: 0
      t.boolean    :required, null: false, default: false
      t.integer    :min_selections, null: false, default: 0
      t.integer    :max_selections
      t.integer    :position, null: false, default: 0

      t.timestamps
    end

    add_index :catalog_item_options, [ :catalog_item_id, :position ]

    create_table :catalog_item_option_values do |t|
      t.references :catalog_item_option, null: false, foreign_key: true
      t.string     :name, null: false
      t.decimal    :price_delta, precision: 12, scale: 2, null: false, default: "0.0"
      t.string     :currency, null: false, default: "AFN"
      t.boolean    :is_available, null: false, default: true
      t.integer    :position, null: false, default: 0

      t.timestamps
    end

    add_index :catalog_item_option_values, [ :catalog_item_option_id, :position ]
  end
end
