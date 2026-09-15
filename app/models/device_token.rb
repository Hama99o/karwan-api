# Where to send a push. A missed "new order" alert is a lost order, so this is
# never the only delivery mechanism for the restaurant — see docs/NOTES.md.
class DeviceToken < ApplicationRecord
  enum :platform, { android: 0, ios: 1 }, prefix: true

  belongs_to :user

  validates :token, presence: true, uniqueness: true

  scope :active, -> { where(active: true) }

  # Re-registering the same token must not fail, and must move it to whoever is
  # signed in now — the same physical tablet gets handed between staff.
  def self.register!(user:, token:, platform:)
    record = find_or_initialize_by(token: token)
    record.update!(user: user, platform: platform, active: true, last_seen_at: Time.current)
    record
  end

  def deactivate!
    update!(active: false)
  end
end
