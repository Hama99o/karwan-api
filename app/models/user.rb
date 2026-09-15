# Phone number is the identity. There is no password column and no email: the
# only way in is an OTP to this phone.
class User < ApplicationRecord
  include SoftDeletable
  LOCALES = %w[ps fa en].freeze

  enum :active_role, Roles::ALL, prefix: :acting_as
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

  # A role the user does not hold is not switchable to. Returns false rather
  # than raising so a stale client cannot 500 the endpoint.
  def switch_role!(role)
    return false unless role?(role)

    update(active_role: role)
  end

  def phone_verified?
    phone_verified_at.present?
  end

  def display_name
    name.presence || phone
  end
end
