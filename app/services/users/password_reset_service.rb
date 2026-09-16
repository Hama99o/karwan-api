module Users
  # FORGOTTEN PASSWORD — A CODE, NOT A LINK, AND THAT IS FORCED BY CORRECTION 16.
  #
  # `hatiwal-api/app/mailers/user_mailer.rb` (read, per correction 15) sends a
  # reset LINK to `WEB_RESET_URL` — a page on hatiwal.com. **Karwan has no web
  # app and never will**, so there is nowhere for that link to land. The two
  # alternatives are a deep link back into the app, which fails silently from a
  # webview on a cheap Android and cannot be recovered from, and a code the
  # person types. So: a code.
  #
  # ── WHICH IS WHAT THE RETAINED OTP MACHINERY IS ACTUALLY FOR ──────────────
  #
  # Hamma9900 refused the code as a SIGN-IN step and was right: friction on
  # every login, and an SMS bill per login, for a neighbourhood acquired one
  # conversation at a time. None of that argues against a code when somebody
  # has lost their password, which is rare and where the friction is the whole
  # point. He said keep it "for now", disabled rather than deleted; this is the
  # job it keeps.
  #
  # ── ONE THROTTLE, KEYED ON THE PHONE ──────────────────────────────────────
  #
  # The code is always issued against `user.phone`, whichever identifier was
  # typed — the phone is NOT NULL for every account, so it is the one key every
  # user has. That also puts email resets behind the SAME counter that protects
  # the SMS bill, rather than behind a second one nobody tuned.
  class PasswordResetService
    Error = Class.new(StandardError)
    Invalid = Class.new(Error)
    InvalidCode = Class.new(Error)
    Throttled = Class.new(Error)

    # ── ASKING FOR A RESET TELLS YOU NOTHING ────────────────────────────────
    #
    # Same rule as the sign-in form, through a different door: if this endpoint
    # said "no account with that email" it would be the account-existence
    # oracle `PasswordSignInService` exists to close. So an unknown identifier
    # and a known one produce the same answer, and the caller cannot tell which
    # happened.
    #
    # Returns the delivery channel the code WOULD go to — derived from the
    # SHAPE OF THE IDENTIFIER TYPED, never from the account — so the app can
    # say "check your messages" or "check your email" without learning whether
    # anybody is there.
    def self.request!(identifier:, locale: nil)
      # `resolve` returns nil for a blank or unparseable input, and `:sms` is
      # the right answer there: a blank field is not an email address, and this
      # branch issues nothing anyway.
      channel = Identifier.resolve(identifier)&.email? ? :email : :sms
      user = Identifier.find_user(identifier)

      if user
        begin
          _verification, code = OtpVerification.issue!(user.phone)
        rescue OtpVerification::Throttled => e
          # Told apart on purpose, and it is the one leak in this endpoint:
          # being throttled implies an account. The alternative is worse — a
          # silent no-op leaves somebody who really did forget their password
          # tapping a button that does nothing, with no idea they must wait.
          raise Throttled, "too many codes requested; try again in #{e.retry_after_seconds}s"
        end

        deliver(user: user, code: code, channel: channel, locale: locale)
      else
        # SPENT EITHER WAY. bcrypt over the code is the largest deterministic
        # cost in the found branch, so doing it here keeps the two paths
        # roughly comparable. It does NOT equalise delivery, and that residual
        # timing difference is recorded in docs/NOTES.md rather than claimed
        # closed — the message and status are identical, which is the part
        # Hamma9900's instruction was about.
        BCrypt::Password.create(SecureRandom.hex(3))
      end

      { channel: channel }
    end

    # ── SETTING THE NEW PASSWORD ────────────────────────────────────────────
    #
    # Every other session is revoked. A reset is what somebody does when they
    # think another person has their password — leaving that person's tokens
    # alive would make the reset theatre, and on a SHARED HANDSET (AFGHAN_UX
    # §7) the other person is often still holding the phone.
    def self.complete!(identifier:, code:, password:, device_name: nil, platform: nil)
      user = Identifier.find_user(identifier)
      verification = user && OtpVerification.for_phone(user.phone).newest_first.first

      # ONE FAILURE for an unknown identifier, no code issued, an expired code
      # and a wrong code. Told apart, this is the oracle again — and worse,
      # "no code has been sent" against an unknown identifier says outright
      # that no such account exists.
      unless verification&.usable? && verification.verify(code.to_s)
        raise InvalidCode, "that code is not correct, or it has expired — ask for a new one"
      end

      if password.to_s.length < RegistrationService::MIN_PASSWORD_LENGTH
        raise Invalid, "a password needs at least #{RegistrationService::MIN_PASSWORD_LENGTH} characters"
      end

      ActiveRecord::Base.transaction do
        user.update!(password: password)
        user.user_sessions.live.each(&:revoke!)

        # SIGNED IN ON THIS DEVICE, immediately. The alternative is a person who
        # just proved they hold the phone being sent back to the login screen to
        # type the password they set four seconds ago — and `customer` is the
        # role, never a partner one: a reset must not be a way into a role.
        session, token = UserSession.issue!(user, device_name: device_name, platform: platform)
        [ user, token, session ]
      end
    end

    # The copy lives in `Setting` rows for the SAME reason the OTP SMS does
    # (Notifications::OtpSms): neither an SMS nor an email has a device to
    # translate it, so the server holds the words — and because it does, they
    # live somewhere Hamma9900 can paste real Pashto into without a deploy.
    def self.deliver(user:, code:, channel:, locale:)
      locale = (locale.presence || user.locale)

      if channel == :email && user.email.present?
        UserMailer.password_reset(user, code, locale: locale).deliver_later
        return
      end

      result = Notifications::SmsClient.deliver(
        to: user.phone,
        body: Notifications::PasswordResetSms.body(code: code, locale: locale)
      )
      # LOGGED AND REPORTED, never swallowed: "nobody can reset" must not look
      # like "nothing happened".
      Rails.logger.error("[password_reset] delivery failed via #{result.provider}: #{result.error}") unless result.delivered?
    end
    private_class_method :deliver
  end
end
