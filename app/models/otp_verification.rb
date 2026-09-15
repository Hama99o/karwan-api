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

  # Raised when a number has been sent too many codes. Carries `retry_after`
  # so the endpoint can tell the user when to try again — "too many attempts"
  # with no number is the kind of dead end that loses a first-time user, and
  # every user here arrived through a conversation somebody had in person.
  class Throttled < StandardError
    attr_reader :retry_after_seconds

    def initialize(retry_after_seconds)
      @retry_after_seconds = retry_after_seconds
      super("too many codes requested; retry in #{retry_after_seconds}s")
    end
  end

  validates :phone, presence: true
  validates :code_digest, presence: true
  validates :expires_at, presence: true

  scope :for_phone, ->(phone) { where(phone: phone) }
  scope :live, -> { where(consumed_at: nil).where(expires_at: Time.current..) }
  scope :newest_first, -> { order(created_at: :desc) }

  # How many codes this number may still be sent, and when the next one is
  # allowed. Nil `retry_after` means "now".
  #
  # Counted from the rows themselves rather than from a cache, so it survives a
  # restart and cannot be reset by an attacker who can make the cache miss.
  def self.send_allowance(phone)
    window = Setting.fetch("otp_send_window_minutes").minutes
    in_window = for_phone(phone).where(created_at: window.ago..).order(:created_at)
    today = for_phone(phone).where(created_at: 1.day.ago..).order(:created_at)

    if in_window.count >= Setting.fetch("otp_max_sends_per_window")
      return { allowed: false, retry_after_seconds: (in_window.first.created_at + window - Time.current).ceil.clamp(1, nil) }
    end

    if today.count >= Setting.fetch("otp_max_sends_per_day")
      return { allowed: false, retry_after_seconds: (today.first.created_at + 1.day - Time.current).ceil.clamp(1, nil) }
    end

    { allowed: true, retry_after_seconds: nil }
  end

  def self.throttled?(phone)
    !send_allowance(phone)[:allowed]
  end

  # Returns [record, plaintext_code]. The plaintext is returned exactly once,
  # for the SMS sender, and is never stored or logged.
  #
  # Raises Throttled BEFORE generating anything, because the cost we are
  # protecting against is the SMS, not the row.
  def self.issue!(phone)
    allowance = send_allowance(phone)
    raise Throttled, allowance[:retry_after_seconds] unless allowance[:allowed]

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
