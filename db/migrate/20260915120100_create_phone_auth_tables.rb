class CreatePhoneAuthTables < ActiveRecord::Migration[8.1]
  def change
    # A 6-digit code is low-entropy, so it is bcrypt-digested and looked up by
    # PHONE, never by digest. attempts_count is what makes brute force
    # expensive; without it a 6-digit code is a 10^6 guess away.
    create_table :otp_verifications do |t|
      t.string   :phone, null: false
      t.string   :code_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.integer  :attempts_count, null: false, default: 0

      t.timestamps
    end

    add_index :otp_verifications, [ :phone, :created_at ]
    add_index :otp_verifications, :expires_at

    # Session tokens are 256-bit random, so they are HMAC-SHA256 digested
    # (deterministic, therefore indexable) rather than bcrypt: bcrypt is salted
    # per row and cannot be looked up by digest at all. The entropy — not the
    # KDF — is what makes these unguessable.
    create_table :user_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.string     :token_digest, null: false
      t.string     :device_name
      t.string     :platform
      t.datetime   :expires_at
      t.datetime   :last_used_at
      t.datetime   :revoked_at

      t.timestamps
    end

    add_index :user_sessions, :token_digest, unique: true

    # Push targets. A missed "new order" alert is a lost order, not an
    # annoyance, and the merchant alert must never rely on one mechanism —
    # push here, plus in-app polling, plus an SMS/phone path.
    #
    # NOT in the brief's data model section; added because v0 scope includes
    # merchant alerts and they need somewhere to send. Flagged to Hamma9901.
    create_table :device_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.string     :token, null: false
      t.integer    :platform, null: false, default: 0
      t.boolean    :active, null: false, default: true
      t.datetime   :last_seen_at

      t.timestamps
    end

    add_index :device_tokens, :token, unique: true
    add_index :device_tokens, [ :user_id, :active ]
  end
end
