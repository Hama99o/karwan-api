# EMAIL OR PHONE, ONE PASSWORD. Hamma9900's own words: *"We will not use OTP.
# We will have login simple with email and password or phone number and
# password."* And: *"for now no authentication"* — meaning no VERIFICATION
# step, not no auth; he described the login in the sentence before it.
#
# ── WHY REQUIRING AN EMAIL IS SAFE HERE ───────────────────────────────────
# Installing from the Play Store requires a Google account, so every user who
# downloads the app the normal way already has Gmail — possessing the app is
# proof of it. That overturns the objection that a large share of Afghan users
# have no email: it does not apply to anyone who installed it from Play.
#
# ── WHY THE PHONE REMAINS A CREDENTIAL, NOT JUST CONTACT DATA ─────────────
# Two real exceptions, and the dual identifier is what makes them work rather
# than being a compromise between two options:
#
#   · SIDELOADED APKs. Sharing an APK over Bluetooth or WhatsApp is common in
#     Afghanistan, and those users may have no Google account at all.
#   · SHARED PHONES (AFGHAN_UX.md §7). If the handset's Gmail belongs to a
#     brother and the sister registers, the account identity is confused. She
#     uses her own number.
#
# ── WHAT THIS MIGRATION DOES NOT DO: make `email` NOT NULL ────────────────
# Existing rows have no email, and the only thing to backfill from is the
# phone — which means writing `+93700000801@something` into a CREDENTIAL
# column. A fabricated address is worse than a null one: it is unique, it looks
# real, and it collides with a real address eventually. So the column is
# nullable with a unique index, the model requires it where it should be
# required, and pre-launch rows sign in by phone.
#
# `encrypted_password` rather than `password_digest`: that is Devise's column,
# and Devise is what Hamma9900 asked for — *"we use same as Hatiwal for now."*
# `hatiwal-api/app/models/user.rb` declares
# `devise :database_authenticatable, :registerable, :confirmable, :recoverable,
# :rememberable, :validatable, :trackable`; this takes the credential and the
# reset and leaves the rest, for reasons in `app/models/user.rb`.
class AddPasswordCredentialsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :email, :string
    # Devise's own column name and default, so `database_authenticatable`
    # behaves exactly as it does in Hatiwal.
    add_column :users, :encrypted_password, :string, null: false, default: ""
    add_column :users, :reset_password_token, :string
    add_column :users, :reset_password_sent_at, :datetime

    # CASE-INSENSITIVE UNIQUENESS, on the stored value: nobody types their
    # address the same way twice, and `Ahmad@Gmail.com` signing up beside
    # `ahmad@gmail.com` is two accounts for one person and a support call
    # nobody can resolve. The model downcases on write; the index is the
    # guarantee.
    add_index :users, :email, unique: true, where: "email IS NOT NULL"
    add_index :users, :reset_password_token, unique: true
  end
end
