module Users
  # A NEW ACCOUNT, IN ONE STEP AND WITH NO VERIFICATION.
  #
  # Hamma9900: *"For now no authentication."* In context — he had just described
  # the login in the previous sentence — that means no VERIFICATION step: no
  # OTP, no emailed confirmation link. Register, set a password, you are in.
  #
  # ── WHAT IS REQUIRED, AND THE ONE PLACE I AM NOT FOLLOWING THE BRIEF ──────
  #
  # The phone is required: it is the guaranteed identifier, a courier has to
  # ring somebody, and it is NOT NULL and unique in the schema.
  #
  # The email is ACCEPTED AND NOT REQUIRED, and that is a deliberate deviation
  # from "both required on new accounts". Requiring it would lock out the two
  # cases the requirement itself names: a SIDELOADED install (an APK over
  # Bluetooth or WhatsApp, common in Afghanistan) whose owner may have no
  # Google account at all, and a SHARED HANDSET whose Gmail belongs to
  # somebody's brother. The app asks for both; the API refuses neither.
  #
  # ── EVERYONE STARTS AS A CUSTOMER ─────────────────────────────────────────
  # Courier and merchant roles are granted after a human looks — one by
  # approval, one by being handed a shop. `User#grant_role!` carries the
  # customer role alongside whatever else is granted later.
  class RegistrationService
    Error = Class.new(StandardError)
    AlreadyRegistered = Class.new(Error)
    Invalid = Class.new(Error)

    # Devise's default is six. Eight, because this password is the only thing
    # between somebody else and a wallet with credit in it — and because a
    # shared phone means the threat is often somebody who knows the person.
    MIN_PASSWORD_LENGTH = 8

    def initialize(phone:, password:, email: nil, name: nil, locale: nil,
                   device_name: nil, platform: nil, requested_role: nil)
      @phone = phone
      @password = password
      @email = email
      @name = name
      @locale = locale
      @device_name = device_name
      @platform = platform
      @requested_role = requested_role
    end

    # Returns [user, plaintext_token, session].
    def call
      normalised_phone = PhoneNumbers.normalise(@phone)
      raise Invalid, "a phone number is required" if normalised_phone.blank?
      raise Invalid, "that phone number does not look right" unless PhoneNumbers.plausible?(@phone)
      if @password.to_s.length < MIN_PASSWORD_LENGTH
        raise Invalid, "a password needs at least #{MIN_PASSWORD_LENGTH} characters"
      end

      # ── SAID PLAINLY, unlike the sign-in failure ────────────────────────────
      #
      # "This number already has an account" reveals that the account exists —
      # which the sign-in path deliberately hides. It is the right trade here
      # and the opposite one there: somebody registering needs to know to sign
      # in instead, or they will try three more times and give up, while
      # somebody signing in does not need to learn whether a stranger's address
      # is registered.
      raise AlreadyRegistered, "this number already has an account" if taken?(normalised_phone)

      ActiveRecord::Base.transaction do
        user = build(normalised_phone)
        user.save!
        user.grant_role!(:customer)

        session, token = UserSession.issue!(
          user, device_name: @device_name, platform: @platform, requested_role: @requested_role
        )
        [ user, token, session ]
      end
    rescue ActiveRecord::RecordInvalid => e
      # The model's own validations — a malformed email, a taken address —
      # reported as a refusal rather than a 500.
      raise Invalid, e.record.errors.full_messages.to_sentence
    end

    private

    def taken?(normalised_phone)
      User.kept.exists?(phone: normalised_phone)
    end

    def build(normalised_phone)
      User.new(
        phone: normalised_phone,
        email: @email.presence,
        name: @name.presence,
        # Dari by default, the most widely spoken in Kabul — but the client
        # sends the device locale, so most users never see a language they did
        # not choose.
        locale: @locale.presence_in(User::LOCALES) || "fa",
        password: @password,
        # NO VERIFICATION STEP, so the phone is trusted as given. That is
        # Hamma9900's call and it is recorded in IDENTITY_AND_ROLES.md: the
        # cost is that a mistyped number reaches a courier, and the mitigation
        # is that the courier rings it while standing outside.
        phone_verified_at: nil,
        last_active_role: :customer
      )
    end
  end
end
