# A courier: operational state plus the onboarding record.
#
# One pool for both demand types. The same human delivers a meal and carries a
# passenger, with one wallet and one commission — the UI says "rider" in the
# food tab and "driver" in the ride tab. Two tables would mean two balances for
# one person, which is how someone ends up blocked from food work while holding
# credit for rides.
#
# Courier registration is nothing like a customer's. A customer is a phone, an
# OTP and a name, because every extra field is a customer lost. A courier
# advances our restaurants' food out of their own pocket and carries our cash,
# so they need identity, a guarantor, documents, and a human approval with a
# name attached. None of it can be collected after the fact.
class CourierProfile < ApplicationRecord
  # Foreground tracking only, while a job is active. A fix older than this is
  # not a location, it is a memory — dispatch must not offer work based on where
  # someone was an hour ago.
  STALE_AFTER = 5.minutes

  enum :vehicle_type, { motorbike: 0, bicycle: 1, car: 2, on_foot: 3 }, prefix: :by
  enum :verification_status, { pending: 0, approved: 1, rejected: 2, suspended: 3 },
       prefix: :verification

  belongs_to :user
  belongs_to :verified_by, class_name: User.name, optional: true

  # A tazkira photo and a face. Held because someone carrying cash and food we
  # paid for has to be identifiable, not because anyone enjoys collecting them.
  has_one_attached :id_document
  has_one_attached :selfie
  has_one_attached :vehicle_photo

  validates :full_name, :national_id_number, :guarantor_name, :guarantor_phone,
            presence: true, if: :verification_approved?
  validate :accepts_at_least_one_demand_type, if: :verification_approved?

  scope :available, -> { where(is_available: true) }
  # The only couriers dispatch may consider for each demand type: approved, on
  # shift, and willing to take that kind of work.
  scope :for_food_orders, -> { verification_approved.available.where(accepts_food_orders: true) }
  scope :for_trips,       -> { verification_approved.available.where(accepts_trips: true) }

  def location_fresh?
    location_updated_at.present? && location_updated_at > STALE_AFTER.ago
  end

  def coordinates
    return nil unless last_latitude && last_longitude

    [ last_latitude, last_longitude ]
  end

  def record_location!(latitude:, longitude:)
    update!(last_latitude: latitude, last_longitude: longitude, location_updated_at: Time.current)
  end

  # Approval is a human decision and must carry a name. A nil approver on an
  # approved courier is not a valid state — it is how "who let this person in?"
  # becomes unanswerable.
  def approve!(by:)
    update!(verification_status: :approved, verified_at: Time.current, verified_by: by,
            rejection_reason: nil)
  end

  def reject!(by:, reason:)
    update!(verification_status: :rejected, verified_at: Time.current, verified_by: by,
            rejection_reason: reason, is_available: false)
  end

  # Can this courier be offered this kind of job at all? A funded wallet is
  # checked separately, per job, because it depends on that job's commission.
  def dispatchable_for?(demand_type)
    return false unless verification_approved? && is_available?

    case demand_type.to_sym
    when :food_order then accepts_food_orders?
    when :trip       then accepts_trips?
    else false
    end
  end

  private

  # An approved courier who accepts neither kind of work can never be offered
  # anything. That is not a courier, it is a silent dead end in the dispatch
  # loop — and it would look like "no couriers available" rather than a
  # misconfigured account.
  def accepts_at_least_one_demand_type
    return if accepts_food_orders? || accepts_trips?

    errors.add(:base, "an approved courier must accept food orders, trips, or both")
  end
end
