# Phone number is the identity. There is no password column and no email: the
# only way in is an OTP to this phone.
class User < ApplicationRecord
  include SoftDeletable
  LOCALES = %w[ps fa en].freeze

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
end
