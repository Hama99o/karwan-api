class AddOnboardingToRidersAndRestaurants < ActiveRecord::Migration[8.1]
  # Customer registration is a phone number, an OTP and a name — nothing more,
  # because every extra field is a customer lost.
  #
  # Rider and restaurant registration is nothing like it. Both are people we
  # hand money and reputation to: a rider advances our restaurants' food out of
  # their own pocket and carries our cash, and a restaurant takes our customers'
  # orders under our name. Both therefore need identity, a guarantor or a
  # licence, documents, and an explicit human approval step. None of this can be
  # collected later — an unverified rider who disappears with a float is exactly
  # the loss this data exists to prevent.
  def change
    change_table :rider_profiles, bulk: true do |t|
      # Afghan identity is a tazkira, and a father's name is part of how a
      # person is identified — two riders named Ahmad are distinguished by it.
      t.string :full_name
      t.string :father_name
      t.string :national_id_number

      t.integer :vehicle_type, null: false, default: 0
      t.string  :plate_number

      # A guarantor is the real trust mechanism here, not a credit check.
      # Someone who vouches for the rider and can be called.
      t.string :guarantor_name
      t.string :guarantor_phone
      t.string :guarantor_relation

      t.text :work_area

      # Explicitly a human decision, with a name attached to it.
      t.integer  :verification_status, null: false, default: 0
      t.datetime :verified_at
      t.bigint   :verified_by_id
      t.text     :rejection_reason
    end

    add_index :rider_profiles, :verification_status
    add_index :rider_profiles, :national_id_number
    add_foreign_key :rider_profiles, :users, column: :verified_by_id

    change_table :restaurants, bulk: true do |t|
      # The owner as a person, separate from the business. In v0 the owner may
      # have no account at all (admin onboards them), so these are plain columns
      # rather than a join to users.
      t.string :owner_name
      t.string :owner_phone
      t.string :owner_national_id_number

      t.string :license_number

      # Who actually answers the phone during a rush — often not the owner.
      t.string :contact_person_name
      t.string :contact_person_phone

      t.datetime :verified_at
      t.bigint   :verified_by_id
      t.text     :rejection_reason
    end

    add_index :restaurants, :owner_phone
    add_foreign_key :restaurants, :users, column: :verified_by_id
  end
end
