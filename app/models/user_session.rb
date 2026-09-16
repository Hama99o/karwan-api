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

  # WHICH MODE THIS DEVICE IS IN. Per session rather than per user, because one
  # human runs a merchant tablet on a counter and a phone in his pocket, and a
  # courier whose phone dies mid-shift signs in on a second one. Switching to
  # the customer tab on one must not flip the other.
  enum :active_role, Roles::ALL, prefix: :acting_as

  validates :token_digest, presence: true, uniqueness: true

  scope :live, -> { where(revoked_at: nil).where(expires_at: [ nil, Time.current.. ]) }

  # Returns [record, plaintext_token]. The plaintext is returned exactly once.
  #
  # `requested_role` is what the sign-in screen asked for. It is a REQUEST, not
  # an instruction: a role the person does not hold, or one that has no place on
  # a phone, falls back rather than failing, because the OTP has already been
  # consumed by the time we get here and stranding someone with no token would
  # cost them a second SMS — which is money, and the only per-order cost in v0.
  def self.issue!(user, device_name: nil, platform: nil, requested_role: nil)
    token = SecureRandom.urlsafe_base64(32)
    record = create!(
      user: user,
      token_digest: digest(token),
      device_name: device_name,
      platform: platform,
      active_role: resolve_role(user, requested_role),
      expires_at: TTL.from_now,
      last_used_at: Time.current
    )
    [ record, token ]
  end

  # WHY A REQUESTED ROLE WAS NOT GRANTED, or nil when there is nothing to say.
  #
  # Two different refusals, because they need two different screens: a role
  # this person could apply for, and a role that does not exist on a phone at
  # all. "Told plainly and offered the application path" is the requirement,
  # and it cannot be honoured by one flat error.
  def self.role_refusal(user, requested)
    return nil if requested.blank?

    requested = requested.to_s
    return :not_a_mobile_role unless Roles::MOBILE.include?(requested)
    return :role_not_held unless user.role?(requested)

    nil
  end

  # What a new session actually opens in: the requested role when it was
  # granted, otherwise where this person left off.
  def self.resolve_role(user, requested)
    return requested.to_s if requested.present? && role_refusal(user, requested).nil?

    seeded_role_for(user)
  end

  # A NEW device starts where the person left off — a reinstall must not drop a
  # courier back into the customer tab, and a reinstall is a new session, so
  # the preference has to live on the user for this to be possible at all.
  #
  # Checked against the roles they STILL hold: a courier whose approval was
  # revoked would otherwise be seeded straight back into a tab with no jobs in
  # it and no way to explain why.
  def self.seeded_role_for(user)
    preferred = user.last_active_role
    return "customer" unless Roles::MOBILE.include?(preferred)

    user.role?(preferred) ? preferred : "customer"
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

  # ONE ACCOUNT, SEVERAL ROLES — and the switch belongs to THIS device.
  #
  # Returns false when the role is refused — the user does not hold it, or it
  # is `admin`, which has no place on a phone. A stale client asking for a role
  # it lost must get a clean refusal rather than a 500, but a write that
  # actually fails must raise — `update` returning
  # false made those two cases indistinguishable, so a failed save read as "you
  # do not hold that role", which is a lie the client then shows the user.
  #
  # The preference is written through, so the NEXT device and the next
  # reinstall open in the same mode.
  def switch_role!(role)
    return false if role.blank?
    return false unless self.class.role_refusal(user, role).nil?

    transaction do
      update!(active_role: role)
      user.update!(last_active_role: role)
    end
    true
  end
end
