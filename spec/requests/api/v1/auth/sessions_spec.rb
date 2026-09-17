require "rails_helper"

RSpec.describe "Api::V1::Auth::Sessions", type: :request do
  let(:phone) { "+93700000123" }

  def json
    JSON.parse(response.body)
  end

  # ── THE OTP FLOW IS RETAINED AND SWITCHED OFF ───────────────────────────────
  #
  # Hamma9900, after seeing the code field on a device: *"We will not use OTP.
  # We will have login simple with email and password or phone number and
  # password."* And *"we don't need this."*
  #
  # It is disabled behind `otp_sign_in_enabled` rather than deleted, because he
  # said "for now" — the table, the throttle and the SMS adapter are built and
  # tested, and deleting them is work now and work again later.
  #
  # So the examples that drive it TURN IT ON first. That is the only honest way
  # to keep them: a retained flow nothing exercises is a flow that has quietly
  # rotted by the time somebody switches it back on.
  def enable_otp!
    Setting.find_or_initialize_by(key: "otp_sign_in_enabled")
           .update!(value: "true", value_type: :boolean)
  end

  def request_code(for_phone = phone)
    post "/api/v1/auth/otp", params: { phone: for_phone }
    JSON.parse(response.body).fetch("development_code")
  end

  describe "POST /api/v1/auth/session" do
    describe "the happy path" do
      before { enable_otp! }

      # Sign-up and sign-in are the same action. Nobody should have to choose
      # between "register" and "log in".
      it "creates the account and signs in a brand new number" do
        code = request_code

        expect { post "/api/v1/auth/session", params: { phone: phone, code: code, name: "احمد کریمی", locale: "ps" } }
          .to change(User, :count).by(1)

        expect(response).to have_http_status(:created)
        expect(json["token"]).to be_present
        expect(json.dig("user", "phone")).to eq(phone)
        expect(json.dig("user", "name")).to eq("احمد کریمی")
        expect(json.dig("user", "locale")).to eq("ps")
        expect(json.dig("user", "roles")).to eq([ "customer" ])
      end

    # ── WHICH DOOR THEY CAME IN BY ───────────────────────────────────────────
    #
    # The role is chosen AT SIGN-IN, not discovered afterwards. Customer is the
    # default and is never asked; "sign in as partner" is a quieter second
    # action that sends a role.
    describe "the role asked for at the door" do
      before { enable_otp! }

      it "opens in the customer tab when nothing is asked" do
        code = request_code

        post "/api/v1/auth/session", params: { phone: phone, code: code }

        expect(json.dig("user", "active_role")).to eq("customer")
        # Nothing was refused, so there is nothing to say about it.
        expect(json).not_to have_key("role_request")
      end

      it "opens in the courier tab for a courier who asked for it" do
        courier = create(:user, :courier, phone: phone)
        code = request_code

        post "/api/v1/auth/session", params: { phone: phone, code: code, role: "courier" }

        expect(json.dig("user", "active_role")).to eq("courier")
        expect(courier.user_sessions.last.active_role).to eq("courier")
        expect(json).not_to have_key("role_request")
      end

      it "opens in the merchant tab for a merchant owner who asked for it" do
        create(:user, :merchant_owner, phone: phone)
        code = request_code

        post "/api/v1/auth/session", params: { phone: phone, code: code, role: "merchant_owner" }

        expect(json.dig("user", "active_role")).to eq("merchant_owner")
      end

      # THE FRONT DOOR TO ONBOARDING. Somebody who taps "sign in as a rider"
      # before applying is the person we most want to reach, and until now the
      # app had no entrance to courier registration at all. So sign-in must
      # still SUCCEED — the code has already been consumed, and failing here
      # would cost them a second SMS, which is real money in this business —
      # and the refusal rides along beside the token.
      it "signs a would-be courier in as a customer and says why" do
        create(:user, phone: phone)
        code = request_code

        post "/api/v1/auth/session", params: { phone: phone, code: code, role: "courier" }

        expect(response).to have_http_status(:created)
        expect(json["token"]).to be_present
        expect(json.dig("user", "active_role")).to eq("customer")
        # AND WHERE TO APPLY. "Tell to create account... they have different
        # form to submit" — so the refusal carries the door to knock on, which
        # is the front entrance courier registration never had from the app.
        expect(json["role_request"]).to eq(
          "requested" => "courier", "granted" => false, "code" => "role_not_held",
          "apply_to" => "/api/v1/courier/registration"
        )
      end

      # A DIFFERENT REFUSAL, because it needs a different screen: there is
      # nothing to apply for. Correction 16 — no admin role in the mobile app,
      # because nothing that can credit a wallet belongs on a shared phone.
      it "refuses the admin role even to a real admin, and says it is not a phone role" do
        admin = create(:user, :admin, phone: phone)
        code = request_code

        post "/api/v1/auth/session", params: { phone: phone, code: code, role: "admin" }

        expect(response).to have_http_status(:created)
        expect(json.dig("user", "active_role")).to eq("customer")
        expect(json.dig("role_request", "code")).to eq("not_a_mobile_role")
        # NOTHING TO APPLY FOR, so no path — the app must say something
        # different here, not offer a form that does not exist.
        expect(json.dig("role_request", "apply_to")).to be_nil
        # And the app is never even offered admin as a role it could switch to.
        expect(json.dig("user", "roles")).to include("customer"), "no roles at all — the check below is vacuous"
        expect(json.dig("user", "roles")).not_to include("admin")
        expect(admin.user_sessions.last.active_role).to eq("customer")
      end

      it "points a would-be restaurant at the lead form, not at an error" do
        create(:user, phone: phone)
        code = request_code

        post "/api/v1/auth/session", params: { phone: phone, code: code, role: "merchant_owner" }

        expect(response).to have_http_status(:created)
        expect(json.dig("role_request", "code")).to eq("role_not_held")
        expect(json.dig("role_request", "apply_to")).to eq("/api/v1/merchant_application")
      end

      it "treats a role that does not exist the same way" do
        create(:user, phone: phone)
        code = request_code

        post "/api/v1/auth/session", params: { phone: phone, code: code, role: "wizard" }

        expect(json.dig("user", "active_role")).to eq("customer")
        expect(json.dig("role_request", "code")).to eq("not_a_mobile_role")
      end

      # One phone, one role. Three phones can hold three roles at once, which
      # is the whole reason the role moved onto the session.
      it "leaves a second device signed in as whatever it chose" do
        user = create(:user, :courier, phone: phone)
        partner_session, = UserSession.issue!(user, requested_role: "courier")
        code = request_code

        post "/api/v1/auth/session", params: { phone: phone, code: code }

        expect(json.dig("user", "active_role")).to eq("courier"), "the preference seeds a new device"
        expect(partner_session.reload.active_role).to eq("courier")
      end
    end

      it "signs in an existing number without creating a second account" do
        create(:user, phone: phone, name: "Existing")
        code = request_code

        expect { post "/api/v1/auth/session", params: { phone: phone, code: code } }
          .not_to change(User, :count)

        expect(response).to have_http_status(:created)
        expect(json.dig("user", "name")).to eq("Existing")
      end

      it "returns a token that actually authenticates" do
        code = request_code
        post "/api/v1/auth/session", params: { phone: phone, code: code }
        token = json["token"]

        expect(UserSession.authenticate(token)).to be_present
      end

      it "records the device, so a person can revoke one phone and not the other" do
        code = request_code

        post "/api/v1/auth/session", params: { phone: phone, code: code,
                                               device_name: "Pixel 6a", platform: "android" }

        expect(UserSession.last).to have_attributes(device_name: "Pixel 6a", platform: "android")
      end

      # Replay is how an intercepted SMS becomes a login an hour later. The
      # code returned is `otp_expired`, not `otp_invalid`, so the app offers
      # "send a new code" rather than "check the digits" — telling someone
      # "no code has been sent" when they are holding the SMS is worse than
      # useless.
      it "consumes the code, so it cannot be replayed" do
        code = request_code
        post "/api/v1/auth/session", params: { phone: phone, code: code }

        post "/api/v1/auth/session", params: { phone: phone, code: code }

        expect(response).to have_http_status(:unprocessable_content)
        expect(json["code"]).to eq("otp_expired")
      end

      it "tells the app whether there is a role to switch to" do
        code = request_code
        post "/api/v1/auth/session", params: { phone: phone, code: code }

        expect(json.dig("user", "can_switch_roles")).to be false
      end
    end

    describe "the refused paths" do
      before { enable_otp! }

      it "refuses a wrong code" do
        request_code

        post "/api/v1/auth/session", params: { phone: phone, code: "000000" }

        expect(response).to have_http_status(:unprocessable_content)
        expect(json["code"]).to eq("otp_invalid")
        expect(UserSession.count).to eq(0)
      end

      it "refuses when no code was ever sent" do
        post "/api/v1/auth/session", params: { phone: phone, code: "123456" }

        expect(response).to have_http_status(:unprocessable_content)
        expect(json["code"]).to eq("otp_not_issued")
      end

      it "refuses an expired code, and says it expired rather than that none was sent" do
        code = request_code
        OtpVerification.for_phone(phone).update_all(expires_at: 1.minute.ago)

        post "/api/v1/auth/session", params: { phone: phone, code: code }

        expect(response).to have_http_status(:unprocessable_content)
        expect(json["code"]).to eq("otp_expired")
      end

      it "says no code was issued only when that is actually true" do
        post "/api/v1/auth/session", params: { phone: phone, code: "123456" }

        expect(json["code"]).to eq("otp_not_issued")
      end

      it "refuses once the guesses are exhausted, even with the right code" do
        code = request_code
        OtpVerification::MAX_ATTEMPTS.times do
          post "/api/v1/auth/session", params: { phone: phone, code: "000000" }
        end

        post "/api/v1/auth/session", params: { phone: phone, code: code }

        expect(response).to have_http_status(:unprocessable_content)
        expect(json["code"]).to eq("otp_expired")
        expect(UserSession.count).to eq(0)
      end

      it "refuses a suspended account and says why" do
        create(:user, :suspended, phone: phone)
        code = request_code

        post "/api/v1/auth/session", params: { phone: phone, code: code }

        expect(response).to have_http_status(:forbidden)
        expect(json["code"]).to eq("account_unavailable")
      end

      it "is a clean 400 when a parameter is missing" do
        post "/api/v1/auth/session", params: { phone: phone, code: "" }

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    # ── THE LIVE LOGIN: ONE FIELD, EITHER IDENTIFIER, ONE PASSWORD ────────────
    #
    # Hamma9900, after seeing the code screen on a device: *"We will not use
    # OTP. We will have login simple with email and password or phone number
    # and password."*
    #
    # One input rather than two or a toggle: two fields is a decision the user
    # has to make and a screen they can get wrong, and AFGHAN_UX asks for the
    # fewest taps and the fewest choices.
    describe "signing in with a password" do
      let(:password) { "a-long-enough-password" }
      let!(:user) do
        create(:user, :customer, phone: "+93700000801", email: "ahmad@gmail.com",
                                 password: password)
      end

      def sign_in(identifier:, secret: password)
        post "/api/v1/auth/session", params: { identifier: identifier, password: secret }
      end

      it "signs in with an email" do
        sign_in(identifier: "ahmad@gmail.com")

        expect(response).to have_http_status(:created)
        expect(json["token"]).to be_present
        expect(json.dig("user", "phone")).to eq("+93700000801")
      end

      it "signs in with a phone number" do
        sign_in(identifier: "+93700000801")

        expect(response).to have_http_status(:created)
        expect(json["token"]).to be_present
      end

      # THE FORM AN AFGHAN USER ACTUALLY TYPES. Without normalising before the
      # lookup this is a stranger, and the app would offer to register them a
      # second account — with its own wallet.
      it "signs in with a LOCAL number, which is what people type" do
        sign_in(identifier: "0700000801")

        expect(response).to have_http_status(:created)
      end

      it "does not care about the case of an email" do
        sign_in(identifier: "AHMAD@Gmail.com")

        expect(response).to have_http_status(:created)
      end

      # ── ONE FAILURE FOR EVERY WRONG CREDENTIAL ─────────────────────────────
      #
      # Told apart, this endpoint is an ACCOUNT-EXISTENCE ORACLE: type an
      # address, learn whether that person uses Karwan. In one Kabul
      # neighbourhood where everyone knows everyone that is a real privacy
      # leak, and the people most exposed are the ones AFGHAN_UX §7 is about.
      it "gives the SAME answer for a wrong password and an unknown account" do
        sign_in(identifier: "ahmad@gmail.com", secret: "wrong-password-entirely")
        wrong_password = [ response.status, json["code"], json["error"] ]

        sign_in(identifier: "nobody@example.com")
        unknown_account = [ response.status, json["code"], json["error"] ]

        expect(wrong_password).to eq(unknown_account)
        expect(json["code"]).to eq("invalid_credentials")
      end

      it "gives that same answer for an unknown phone number" do
        sign_in(identifier: "+93700009999")

        expect(json["code"]).to eq("invalid_credentials")
      end

      # An account from before passwords existed. Not broken and not locked
      # out — it resets, which is what `:recoverable` is for — but it must not
      # be distinguishable from a wrong password either.
      it "gives that same answer for an account with no password yet" do
        create(:user, :passwordless, phone: "+93700000777", email: "old@account.af")

        sign_in(identifier: "old@account.af")

        expect(json["code"]).to eq("invalid_credentials")
      end

      it "gives that same answer for a deleted account" do
        user.discard!

        sign_in(identifier: "ahmad@gmail.com")

        expect(json["code"]).to eq("invalid_credentials")
      end

      # SUSPENSION IS THE ONE CASE TOLD APART, because the password was RIGHT:
      # "try again" would be a lie, and that person needs to ring support.
      it "tells a suspended account the truth, because its password was right" do
        user.update!(status: :suspended)

        sign_in(identifier: "ahmad@gmail.com")

        expect(response).to have_http_status(:forbidden)
        expect(json["code"]).to eq("account_unavailable")
      end

      it "refuses a blank password without pretending to check it" do
        sign_in(identifier: "ahmad@gmail.com", secret: "")

        expect(json["code"]).to eq("invalid_credentials")
      end

      # The partner door works the same way it did with a code — the role is
      # asked for at sign-in, whatever the credential.
      it "still carries the role asked for at the door" do
        user.user_roles.create!(role: :courier)

        post "/api/v1/auth/session",
             params: { identifier: "ahmad@gmail.com", password: password, role: "courier" }

        expect(json.dig("user", "active_role")).to eq("courier")
      end

      it "still answers with the application path when that role is not held" do
        post "/api/v1/auth/session",
             params: { identifier: "ahmad@gmail.com", password: password, role: "courier" }

        expect(response).to have_http_status(:created)
        expect(json.dig("role_request", "apply_to")).to eq("/api/v1/courier/registration")
      end
    end
  end

  describe "DELETE /api/v1/auth/session" do
    # Signs in through the LIVE flow rather than the retained one: what this
    # example is about is the revoke, and driving it with a password proves the
    # token a real user is holding today is the token that DELETE invalidates.
    it "revokes the session it was called with" do
      create(:user, phone: phone, password: "a-long-enough-password")
      post "/api/v1/auth/session",
           params: { identifier: phone, password: "a-long-enough-password" }
      token = json["token"]

      delete "/api/v1/auth/session", headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:no_content)
      expect(UserSession.authenticate(token)).to be_nil
    end

    # A courier with a phone and a tablet signing out of one must stay signed
    # in on the other.
    it "leaves the user's other sessions alive" do
      user = create(:user, phone: phone)
      _, phone_token = UserSession.issue!(user, device_name: "phone")
      _, tablet_token = UserSession.issue!(user, device_name: "tablet")

      delete "/api/v1/auth/session", headers: { "Authorization" => "Bearer #{phone_token}" }

      expect(UserSession.authenticate(tablet_token)).to be_present
    end

    it "refuses without a token" do
      delete "/api/v1/auth/session"

      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses a token that is not real" do
      delete "/api/v1/auth/session", headers: { "Authorization" => "Bearer nonsense" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses a malformed Authorization header" do
      delete "/api/v1/auth/session", headers: { "Authorization" => "nonsense" }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
