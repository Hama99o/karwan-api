# Phone number is the identity. There is no password column and no email: the
# only way in is an OTP to this phone.
class User < ApplicationRecord
  include SoftDeletable
  include AttachableDocuments

  # HIS WORDS: "we should have user edit profile photo etc also man".
  #
  # Ships WITH its variant rather than joining the problem NOTES.md records —
  # eight attachments, no variants, originals served at full camera resolution.
  # An avatar renders at about 96 px, so 192 px covers a 2x screen and costs
  # ~8 KB against a ~3 MB original.
  #
  # `has_one_attached` validates NOTHING on its own (merchant.rb:43 says so
  # plainly), which is why `validates_attached` is below rather than trusted to
  # the macro.
  has_one_attached :avatar do |attachable|
    attachable.variant :thumb, resize_to_limit: [ 192, 192 ], saver: { quality: 80 }
  end

  validates_attached :avatar
  LOCALES = %w[ps fa en].freeze

  # ── THE CREDENTIAL IS DEVISE'S; THE SESSION IS OURS ─────────────────────────
  #
  # Hamma9900: *"we use same as Hatiwal for now."* `hatiwal-api/app/models/user.rb`
  # declares `devise :database_authenticatable, :registerable, :confirmable,
  # :recoverable, :rememberable, :validatable, :trackable` and includes
  # `DeviseTokenAuth::Concerns::User`. This takes TWO of those modules and
  # leaves the rest, deliberately:
  #
  #   database_authenticatable — the password and `valid_password?`. Proven, and
  #                              nobody should hand-roll a password comparison.
  #   recoverable              — the reset token and the mailer, which is the
  #                              other half of what "no OTP" costs us.
  #
  # NOT `devise_token_auth`: its token store would replace `user_sessions`, and
  # `user_sessions.active_role` is what makes three phones hold three different
  # roles at once (IDENTITY_AND_ROLES.md §4) and what a split app reads its role
  # from (correction 18). Hatiwal never needed either. So Devise owns the
  # credential and `user_sessions` owns the device.
  #
  # NOT `:validatable`: it requires an email, and ours is optional — see below.
  # NOT `:confirmable`: Hamma9900 said *"for now no authentication"*, meaning no
  # verification step. The columns Hatiwal uses for it are not here.
  devise :database_authenticatable, :recoverable

  # ── TWO IDENTIFIERS, ONE PASSWORD ───────────────────────────────────────────
  #
  # The PHONE is the guaranteed one: NOT NULL and unique since the first
  # migration, because a courier has to ring somebody. The EMAIL is the
  # additional one, nullable and unique.
  #
  # That asymmetry fits the market rather than being a compromise. Installing
  # from the Play Store requires a Google account, so a Play user has Gmail —
  # possessing the app is proof of it. A SIDELOADED user (an APK over Bluetooth
  # or WhatsApp, which is common here) may have no Google account at all, and on
  # a SHARED HANDSET (AFGHAN_UX.md §7) the Gmail may belong to somebody's
  # brother. Both of those people have a number.
  #
  # New accounts are asked for both; the guarantee sits on the identifier
  # everybody actually has.
  validates :email, uniqueness: { case_sensitive: false }, allow_nil: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  # STORED DOWNCASED AND NORMALISED, because nobody types either identifier the
  # same way twice. `Ahmad@Gmail.com` beside `ahmad@gmail.com` is two accounts
  # for one person and a support call nobody can resolve; `0700000801` beside
  # `+93700000801` is the same failure on the other field, and worse, because
  # the second account gets its own wallet.
  before_validation :canonicalise_identifiers

  # WHERE THIS PERSON LEFT OFF — a preference, not a state. The live mode lives
  # on the session, because one human can have two devices in two modes; this
  # only seeds the next new one, so a reinstall does not drop a courier back
  # into the customer tab. See `UserSession#switch_role!`.
  enum :last_active_role, Roles::ALL, prefix: :last_acted_as
  enum :status, { active: 0, suspended: 1 }, prefix: :account

  has_many :user_roles, dependent: :destroy
  has_many :addresses, dependent: :destroy
  has_many :user_sessions, dependent: :destroy
  has_many :device_tokens, dependent: :destroy

  # ── FOR THE CONSOLE, AND NEVER THE TOKEN ITSELF ──────────────────────────
  #
  # Two summaries an operator needs and could not get. Same shape as
  # `OrderItem#options_summary`: a computed string, because the thing an
  # operator must read is a fact ABOUT the rows, not the rows.
  #
  # `user_sessions.token_digest` and `device_tokens.token` are credentials. A
  # console that prints either is a console that leaks a working session or a
  # push target, so neither of these returns one — they answer "how many" and
  # "when", which is the whole operational question.
  def live_session_count
    user_sessions.live.count
  end

  # The first question when a merchant's board stayed silent: is there a tablet
  # registered at all? Pairs with the landing page's "shops to ring" count.
  def registered_devices_summary
    active = device_tokens.active.order(updated_at: :desc)
    return "none registered" if active.empty?

    platforms = active.map(&:platform).tally.map { |p, n| n > 1 ? "#{n} #{p}" : p.to_s }
    "#{active.size} active (#{platforms.join(', ')}) — last #{active.first.updated_at.to_date}"
  end


  has_many :owned_merchants, class_name: Merchant.name, foreign_key: :owner_id,
                               inverse_of: :owner, dependent: :restrict_with_error
  # Demand side: what this person ordered or booked.
  has_many :orders, class_name: Order.name, foreign_key: :customer_id,
                    inverse_of: :customer, dependent: :restrict_with_error
  has_many :trips, class_name: Trip.name, foreign_key: :passenger_id,
                   inverse_of: :passenger, dependent: :restrict_with_error

  # Supply side: what this person fulfilled, across both demand types. One
  # human, one wallet, one commission — the UI says "rider" in the food tab and
  # "driver" in the ride tab.
  has_many :courier_orders, class_name: Order.name, foreign_key: :courier_id,
                            inverse_of: :courier, dependent: :restrict_with_error
  has_many :courier_trips, class_name: Trip.name, foreign_key: :courier_id,
                           inverse_of: :courier, dependent: :restrict_with_error

  has_one :courier_profile, dependent: :destroy
  has_one :courier_wallet, dependent: :destroy

  validates :phone, presence: true, uniqueness: true
  validates :locale, presence: true, inclusion: { in: LOCALES }

  scope :with_role, ->(role) { joins(:user_roles).where(user_roles: { role: UserRole.roles[role] }) }

  def role?(role)
    user_roles.exists?(role: UserRole.roles[role.to_s])
  end

  # GRANTING A PARTNER ROLE ALSO GRANTS CUSTOMER, ALWAYS.
  #
  # Hamma9900's rule, and the asymmetry is the right way round: a courier or a
  # restaurant owner is a customer for free — "it's not a big thing", there is
  # nothing to verify, a customer is just a phone — while the reverse is never
  # automatic and must stay that way.
  #
  # It held only by accident of the path before: `SignInService` creates every
  # account with `:customer`, so anyone who arrived through the app had it. A
  # courier created by a seed, by the console, or by any future admin path did
  # not, and a courier who cannot order food breaks the premise the shared pool
  # rests on — the same human delivers a meal at 13:00 and buys one at 20:00.
  #
  # Idempotent, so it is safe to call on every save.
  def grant_role!(role)
    transaction do
      user_roles.find_or_create_by!(role: role)
      user_roles.find_or_create_by!(role: :customer)
    end
  end

  # Takes a role away, and NEVER the customer role: losing the ability to order
  # food is not a consequence anyone intends when they reassign a restaurant.
  def revoke_role!(role)
    return if role.to_s == "customer"

    user_roles.where(role: UserRole.roles[role.to_s]).destroy_all
  end

  def phone_verified?
    phone_verified_at.present?
  end

  def display_name
    name.presence || phone
  end

  # Whether this account can be signed into with a password at all.
  #
  # False for every account created before passwords existed — they signed in
  # with a code. They are not broken and not locked out: they reset their
  # password, which is what `:recoverable` is for.
  def password_set?
    encrypted_password.present?
  end

  private

  def canonicalise_identifiers
    self.email = email.to_s.strip.downcase.presence
    normalised = PhoneNumbers.normalise(phone)
    self.phone = normalised if normalised.present?
  end
end
