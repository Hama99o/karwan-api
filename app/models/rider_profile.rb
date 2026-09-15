# A rider: operational state plus the onboarding record.
#
# Rider registration is nothing like a customer's. A customer is a phone, an OTP
# and a name, because every extra field is a customer lost. A rider advances our
# restaurants' food out of their own pocket and carries our cash, so they need
# identity, a guarantor, documents, and a human approval with a name attached.
# None of it can be collected after the fact.
class RiderProfile < ApplicationRecord
  # Foreground tracking only, while an order is active. A fix older than this
  # is not a location, it is a memory — dispatch must not offer a job based on
  # where someone was an hour ago.
  STALE_AFTER = 5.minutes

  enum :vehicle_type, { motorbike: 0, bicycle: 1, car: 2, on_foot: 3 }, prefix: :by
  enum :verification_status, { pending: 0, approved: 1, rejected: 2, suspended: 3 },
       prefix: :verification

  belongs_to :user
  belongs_to :verified_by, class_name: User.name, optional: true

  # A tazkira photo and a face. Held because a rider carrying cash and food we
  # paid for has to be identifiable, not because anyone enjoys collecting them.
  has_one_attached :id_document
  has_one_attached :selfie
  has_one_attached :vehicle_photo

  validates :full_name, :national_id_number, :guarantor_name, :guarantor_phone,
            presence: true, if: :verification_approved?

  scope :available, -> { where(is_available: true) }
  # The only riders dispatch may consider: approved, on shift, and with a
  # location recent enough to mean anything.
  scope :dispatchable, -> { verification_approved.available }

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

  # Approval is a human decision and must carry a name. `approved_by` being
  # nil on an approved rider is not a valid state — it is how "who let this
  # person in?" becomes unanswerable.
  def approve!(by:)
    update!(verification_status: :approved, verified_at: Time.current, verified_by: by,
            rejection_reason: nil)
  end

  def reject!(by:, reason:)
    update!(verification_status: :rejected, verified_at: Time.current, verified_by: by,
            rejection_reason: reason, is_available: false)
  end

  # Can this rider be offered work at all? Approval and availability are
  # necessary; a funded wallet is checked separately, per order, because it
  # depends on the order's commission.
  def dispatchable?
    verification_approved? && is_available?
  end
end
