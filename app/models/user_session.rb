# A bearer token for the mobile app.
#
# The token is 256 bits of randomness, so its digest is a keyed HMAC rather than
# bcrypt: bcrypt salts per row and therefore cannot be looked up by digest at
# all, and with this much entropy there is nothing to brute force. The HMAC key
# is secret_key_base, so rotating it invalidates every session — which is the
# behaviour you want from a key rotation.
class UserSession < ApplicationRecord
  TTL = 90.days

  belongs_to :user

  validates :token_digest, presence: true, uniqueness: true

  scope :live, -> { where(revoked_at: nil).where(expires_at: [ nil, Time.current.. ]) }

  # Returns [record, plaintext_token]. The plaintext is returned exactly once.
  def self.issue!(user, device_name: nil, platform: nil)
    token = SecureRandom.urlsafe_base64(32)
    record = create!(
      user: user,
      token_digest: digest(token),
      device_name: device_name,
      platform: platform,
      expires_at: TTL.from_now,
      last_used_at: Time.current
    )
    [ record, token ]
  end

  def self.digest(token)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, token.to_s)
  end

  def self.authenticate(token)
    return nil if token.blank?

    live.find_by(token_digest: digest(token))
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  def touch_usage!
    update_column(:last_used_at, Time.current)
  end
end
