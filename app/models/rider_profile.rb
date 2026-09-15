# Operational rider state. Kept out of rider_wallets so the money table stays
# money-only, and out of users so users stays role-agnostic.
class RiderProfile < ApplicationRecord
  # Foreground tracking only, while an order is active. A fix older than this
  # is not a location, it is a memory — dispatch must not offer a job based on
  # where someone was an hour ago.
  STALE_AFTER = 5.minutes

  belongs_to :user

  scope :available, -> { where(is_available: true) }

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
end
