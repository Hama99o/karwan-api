require "rails_helper"

RSpec.describe "Api::V1::Auth::Sessions", type: :request do
  let(:phone) { "+93700000123" }

  def json
    JSON.parse(response.body)
  end

  def request_code(for_phone = phone)
    post "/api/v1/auth/otp", params: { phone: for_phone }
    JSON.parse(response.body).fetch("development_code")
  end

  describe "POST /api/v1/auth/session" do
    describe "the happy path" do
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
        post "/api/v1/auth/session", params: { phone: phone }

        expect(response).to have_http_status(:bad_request)
      end
    end
  end

  describe "DELETE /api/v1/auth/session" do
    it "revokes the session it was called with" do
      code = request_code
      post "/api/v1/auth/session", params: { phone: phone, code: code }
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
