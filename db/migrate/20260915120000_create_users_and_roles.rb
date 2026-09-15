class CreateUsersAndRoles < ActiveRecord::Migration[8.1]
  def change
    # Phone number is the identity — not email. Everyone in Kabul has a phone;
    # few have email. There is deliberately no encrypted_password column: the
    # only way in is an OTP (see CreatePhoneAuthTables).
    create_table :users do |t|
      t.string   :phone, null: false
      t.string   :name
      t.string   :locale, null: false, default: "fa"
      t.integer  :active_role, null: false, default: 0
      t.integer  :status, null: false, default: 0
      t.datetime :phone_verified_at

      t.timestamps
    end

    add_index :users, :phone, unique: true
    add_index :users, :status

    # One account, several roles, switched in the app. Mirrors hatiwal's
    # buyer/seller mode on one user, extended from two roles to four.
    create_table :user_roles do |t|
      t.references :user, null: false, foreign_key: true
      t.integer    :role, null: false

      t.timestamps
    end

    add_index :user_roles, [ :user_id, :role ], unique: true

    # No street addressing: Afghan addresses are unreliable and people navigate
    # by landmarks. An address IS a map pin + a landmark note + a phone number.
    # Reverse geocoding is a nicety, never the mechanism.
    create_table :addresses do |t|
      t.references :user, null: false, foreign_key: true
      t.string     :label
      t.decimal    :latitude,  precision: 10, scale: 6, null: false
      t.decimal    :longitude, precision: 10, scale: 6, null: false
      t.text       :landmark_note
      t.string     :phone
      t.boolean    :is_default, null: false, default: false

      t.timestamps
    end

    add_index :addresses, [ :user_id, :is_default ]
  end
end
