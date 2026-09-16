module Users
  # Phone + OTP, and nothing else.
  #
  # Correction 10: this must be the simplest thing in the app. No email, no
  # password, no profile-completion wall, no "create an account" framing. A
  # first-time user types a phone number, types six digits, and is in — because
  # the person who convinced them to install this is not standing next to them,
  # and a login screen is where they give up.
  #
  # Sign-up and sign-in are THE SAME ACTION. Asking someone to choose between
  # "register" and "log in" is a decision they should never have to make: if the
  # number is new we create the account, if it is known we sign them in.
  class SignInService
    Error = Class.new(StandardError)
    InvalidCode = Class.new(Error)
    NoCodeIssued = Class.new(Error)
    CodeNoLongerValid = Class.new(Error)

    def initialize(phone:, code:, name: nil, locale: nil, device_name: nil, platform: nil,
                   requested_role: nil)
      @phone = phone.to_s.strip
      @code = code.to_s.strip
      @name = name
      @locale = locale
      @device_name = device_name
      @platform = platform
      # WHICH DOOR THEY CAME IN BY. Customer is the default and is never asked;
      # "sign in as partner" is the quieter second action that sets this.
      @requested_role = requested_role
    end

    # Returns [user, plaintext_token, session]. The session is returned because
    # the mode the app opens in is a fact about it, not about the user.
    def call
      # The newest code for this number, live or not, so the three cases can be
      # told apart. Collapsing them was misleading: someone replaying a
      # consumed code was told "no code has been sent to this number", which is
      # simply untrue and sends them to look for an SMS they already have.
      verification = OtpVerification.for_phone(@phone).newest_first.first
      raise NoCodeIssued, "no code has been sent to this number" if verification.nil?

      unless verification.usable?
        raise CodeNoLongerValid, "that code has expired or has already been used — request a new one"
      end

      raise InvalidCode, "that code is not correct" unless verification.verify(@code)

      ActiveRecord::Base.transaction do
        user = find_or_create_user
        session, token = UserSession.issue!(
          user, device_name: @device_name, platform: @platform,
          requested_role: @requested_role
        )
        [ user, token, session ]
      end
    end

    private

    def find_or_create_user
      user = User.find_by(phone: @phone)

      if user.nil?
        user = User.create!(
          phone: @phone,
          name: @name,
          # Defaults to Dari, the most widely spoken in Kabul, but the client
          # sends the device locale on first sign-in so most users never see a
          # language they did not choose.
          locale: @locale.presence_in(User::LOCALES) || "fa",
          # Everyone's first device opens in the customer tab. This is the
          # PREFERENCE that seeds it; the session holds the live mode.
          last_active_role: :customer,
          phone_verified_at: Time.current
        )
        # Everyone starts as a customer. Courier and merchant roles are granted
        # by admin after verification — they are not self-serve, because both
        # involve handing someone money or reputation.
        user.user_roles.create!(role: :customer)
      else
        # Verifying the code proves they hold the number, whatever the account
        # said before.
        user.update!(phone_verified_at: Time.current)
        user.update!(name: @name) if @name.present? && user.name.blank?
        user.update!(locale: @locale) if @locale.presence_in(User::LOCALES) && user.name.blank?
      end

      raise Error, "this account is suspended" unless user.account_active? && user.kept?

      user
    end
  end
end
