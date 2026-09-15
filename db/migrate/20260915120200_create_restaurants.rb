class CreateRestaurants < ActiveRecord::Migration[8.1]
  def change
    create_table :restaurants do |t|
      # Nullable: admin onboards restaurants in v0, so a restaurant exists
      # before its owner has an account. Restaurants are not self-serve.
      t.references :owner, null: true, foreign_key: { to_table: :users }

      t.string  :name, null: false
      t.string  :phone, null: false
      t.text    :description

      # The single most important control in the whole system. A restaurant
      # marked open that isn't is the most damaging state there is, so it
      # defaults to CLOSED and is only ever opened deliberately.
      t.boolean :is_open, null: false, default: false

      t.integer :prep_time_minutes, null: false, default: 20

      t.decimal :latitude,  precision: 10, scale: 6
      t.decimal :longitude, precision: 10, scale: 6
      t.text    :landmark_note

      # Per-restaurant override of the global commission setting. 0.1250 is the
      # brief's worked example: 50 AFN on 400 AFN of food.
      t.decimal :commission_rate, precision: 5, scale: 4, null: false, default: "0.125"

      t.integer :status, null: false, default: 0

      t.timestamps
    end

    add_index :restaurants, :status
    add_index :restaurants, :is_open
    add_index :restaurants, :name

    # day_of_week uses Ruby's Time#wday — 0 = Sunday — NOT the Afghan week,
    # which starts Saturday. The display order is the client's problem; storing
    # anything but wday means converting on every comparison.
    create_table :restaurant_opening_hours do |t|
      t.references :restaurant, null: false, foreign_key: true
      t.integer    :day_of_week, null: false
      t.time       :opens_at, null: false
      t.time       :closes_at, null: false

      t.timestamps
    end

    add_index :restaurant_opening_hours, [ :restaurant_id, :day_of_week ]
  end
end
