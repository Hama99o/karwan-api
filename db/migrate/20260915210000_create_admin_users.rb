class CreateAdminUsers < ActiveRecord::Migration[8.1]
  # Staff accounts for the ops console, DELIBERATELY SEPARATE from `users`.
  #
  # The mobile side is phone + OTP with no password — right for a courier on a
  # cheap phone, wrong for a human at a desk who can cancel orders and credit
  # wallets. Separate tables mean a customer can never escalate into an admin,
  # and the two surfaces share no authentication code at all.
  #
  # Created out of band (seeds, console). There is no public registration.
  def change
    create_table :admin_users do |t|
      t.string :name, null: false
      t.string :email, null: false, default: ""
      t.string :encrypted_password, null: false, default: ""

      t.string   :reset_password_token
      t.datetime :reset_password_sent_at
      t.datetime :remember_created_at

      # Trackable: who signed in, when, from where. This surface can change
      # anything about anyone, so the sign-in record is part of the audit story.
      t.integer  :sign_in_count, default: 0, null: false
      t.datetime :current_sign_in_at
      t.datetime :last_sign_in_at
      t.string   :current_sign_in_ip
      t.string   :last_sign_in_ip

      # Lockable: an admin password is the highest-value credential in the
      # system and it is reachable from the open internet.
      t.integer  :failed_attempts, default: 0, null: false
      t.string   :unlock_token
      t.datetime :locked_at

      t.timestamps
    end

    add_index :admin_users, :email, unique: true
    add_index :admin_users, :reset_password_token, unique: true
    add_index :admin_users, :unlock_token, unique: true
  end
end
