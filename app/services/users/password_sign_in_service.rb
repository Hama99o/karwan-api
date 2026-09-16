module Users
  # EMAIL OR PHONE, PLUS A PASSWORD. The whole login.
  #
  # Hamma9900, after seeing the OTP screen on a device: *"We will not use OTP.
  # We will have login simple with email and password or phone number and
  # password."* And asked why a code was needed at all: *"we don't need this."*
  #
  # ── THE SAME ERROR FOR AN UNKNOWN ACCOUNT AND A WRONG PASSWORD ────────────
  #
  # Not a nicety. Told apart, this form is an ACCOUNT-EXISTENCE ORACLE: type an
  # address, learn whether that person uses Karwan. In one Kabul neighbourhood
  # where everyone knows everyone, that is a real privacy leak rather than a
  # theoretical one — and the people most exposed by it are exactly the ones
  # `AFGHAN_UX.md` §7 is about.
  #
  # So there is one failure, `invalid_credentials`, for: no such account, a
  # deleted account, an account with no password yet, and a wrong password. The
  # only case that gets its own answer is a SUSPENDED account, because that
  # person needs to be told to ring support rather than left retyping a
  # password that is correct.
  class PasswordSignInService
    Error = Class.new(StandardError)
    InvalidCredentials = Class.new(Error)
    AccountUnavailable = Class.new(Error)

    def initialize(identifier:, password:, device_name: nil, platform: nil, requested_role: nil)
      @identifier = identifier
      @password = password
      @device_name = device_name
      @platform = platform
      @requested_role = requested_role
    end

    # Returns [user, plaintext_token, session].
    def call
      user = Identifier.find_user(@identifier)

      # ── A DELIBERATE CONSTANT-ISH PATH ──────────────────────────────────────
      #
      # The password is verified even when no account was found, against a
      # throwaway digest, so that a missing account and a wrong password take
      # roughly the same time. Without it the RESPONSE TIME is the oracle the
      # shared error message closes — bcrypt is slow enough to measure from
      # Kabul, and "fast rejection means no such user" is a two-line script.
      unless user&.password_set? && user.valid_password?(@password.to_s)
        verify_against_nothing
        raise InvalidCredentials, "that email or number and password do not match"
      end

      # SUSPENSION GETS ITS OWN ANSWER, because the person is not guessing: the
      # password was right, and telling them to try again would be a lie.
      raise AccountUnavailable, "this account is suspended" unless user.account_active?

      session, token = UserSession.issue!(
        user, device_name: @device_name, platform: @platform, requested_role: @requested_role
      )
      [ user, token, session ]
    end

    private

    # One bcrypt comparison against a digest of nothing anybody holds.
    def verify_against_nothing
      Devise::Encryptor.compare(User, DECOY_DIGEST, @password.to_s)
    end

    # A real bcrypt digest of a password nobody has. Computed once at boot
    # rather than per request — the point is to spend the same time, not to be
    # unguessable.
    DECOY_DIGEST = Devise::Encryptor.digest(User, SecureRandom.hex(16)).freeze
  end
end
