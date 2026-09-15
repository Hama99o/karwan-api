class AddRestaurantOnboarding < ActiveRecord::Migration[8.1]
  # Customer registration is a phone number, an OTP and a name — nothing more,
  # because every extra field is a customer lost.
  #
  # A restaurant is nothing like it: it takes our customers' orders under our
  # name, so it needs the owner as an identifiable person, a licence, and a
  # human approval. The courier equivalent lives in `courier_profiles`.
  def change
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
