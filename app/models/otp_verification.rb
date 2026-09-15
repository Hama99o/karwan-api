# A one-time code sent to a phone number.
#
# Six digits is 10^6 guesses, which is nothing, so the protection is not the
# digest — it is MAX_ATTEMPTS plus a short TTL. bcrypt is used anyway because
# the row is looked up by phone, so a salted digest costs nothing here, and a
# leaked database should not hand over live codes.
class OtpVerification < ApplicationRecord
  CODE_LENGTH  = 6
  TTL          = 5.minutes
  MAX_ATTEMPTS = 5

  validates :phone, presence: true
  validates :code_digest, presence: true
  validates :expires_at, presence: true

  scope :for_phone, ->(phone) { where(phone: phone) }
  scope :live, -> { where(consumed_at: nil).where(expires_at: Time.current..) }
  scope :newest_first, -> { order(created_at: :desc) }

  # Returns [record, plaintext_code]. The plaintext is returned exactly once,
  # for the SMS sender, and is never stored or logged.
  def self.issue!(phone)
    code = SecureRandom.random_number(10**CODE_LENGTH).to_s.rjust(CODE_LENGTH, "0")
    record = create!(
      phone: phone,
      code_digest: BCrypt::Password.create(code),
      expires_at: TTL.from_now
    )
    [ record, code ]
  end

  def expired?
    expires_at <= Time.current
  end

  def consumed?
    consumed_at.present?
  end

  def attempts_exhausted?
    attempts_count >= MAX_ATTEMPTS
  end

  def usable?
    !consumed? && !expired? && !attempts_exhausted?
  end

  # Increments the attempt counter on every call, INCLUDING successes, so a
  # caller cannot probe indefinitely by mixing in one good guess.
  def verify(code)
    return false unless usable?

    increment!(:attempts_count)
    return false unless BCrypt::Password.new(code_digest) == code.to_s

    update!(consumed_at: Time.current)
    true
  end
end
