require "rails_helper"

RSpec.describe "POST /api/v1/auth/otp", type: :request do
  let(:phone) { "+93700000123" }

  def json
    JSON.parse(response.body)
  end

  describe "the happy path" do
    it "sends a code to a new number" do
      post "/api/v1/auth/otp", params: { phone: phone }

      expect(response).to have_http_status(:ok)
      expect(json["sent"]).to be true
      expect(json["expires_in_seconds"]).to eq(OtpVerification::TTL.to_i)
      expect(OtpVerification.for_phone(phone).count).to eq(1)
    end

    it "sends a code to an existing user without revealing that they exist" do
      create(:user, phone: phone)

      post "/api/v1/auth/otp", params: { phone: phone }
      existing = json

      post "/api/v1/auth/otp", params: { phone: "+93700000999" }

      # Same shape either way. A response that differs would let anyone
      # enumerate which numbers have accounts.
      expect(existing.keys.sort).to eq(json.keys.sort)
    end

    it "needs no authentication, because there is nobody to authenticate yet" do
      post "/api/v1/auth/otp", params: { phone: phone }

      expect(response).to have_http_status(:ok)
    end

    # Cross-border use is deliberate: the app is FOR Afghanistan but not
    # restricted to it, exactly as Hatiwal is not.
    it "accepts a number from outside Afghanistan" do
      post "/api/v1/auth/otp", params: { phone: "+923001234567" }

      expect(response).to have_http_status(:ok)
    end
  end

  describe "the refused paths" do
    it "rejects a blank phone number" do
      post "/api/v1/auth/otp", params: { phone: "" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("phone_required")
    end

    # A machine-readable code rather than a bare 400: the app renders its own
    # Pashto or Dari message from `code`, and cannot translate a 400.
    it "names the problem when the parameter is missing entirely" do
      post "/api/v1/auth/otp", params: {}

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("phone_required")
    end

    # The billing gate, at the layer it actually has to hold.
    it "throttles once the burst limit is reached, and says when to retry" do
      Setting.fetch("otp_max_sends_per_window").times do
        post "/api/v1/auth/otp", params: { phone: phone }
        expect(response).to have_http_status(:ok)
      end

      post "/api/v1/auth/otp", params: { phone: phone }

      expect(response).to have_http_status(:too_many_requests)
      expect(json["code"]).to eq("otp_throttled")
      expect(json["retry_after_seconds"]).to be_positive
    end

    it "throttles per number, so one abused number does not block everyone" do
      Setting.fetch("otp_max_sends_per_window").times { post "/api/v1/auth/otp", params: { phone: phone } }

      post "/api/v1/auth/otp", params: { phone: "+93700000124" }

      expect(response).to have_http_status(:ok)
    end
  end

  describe "the development code hint" do
    # There is no SMS provider yet, so the code comes back in the response and
    # the mobile app can drive a real sign-in. This MUST NOT happen in
    # production.
    it "is present outside production" do
      post "/api/v1/auth/otp", params: { phone: phone }

      expect(json["development_code"]).to match(/\A\d{6}\z/)
    end

    it "is absent in production" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))

      post "/api/v1/auth/otp", params: { phone: phone }

      expect(json).not_to have_key("development_code")
    end
  end
  # THE SMS ITSELF — there was no message at all before: a code was logged and
  # no text was ever composed, on the one thing a Kabul user reads from us
  # first.
  describe "the message that actually gets sent" do
    it "sends a body containing the code, through the one adapter class" do
      expect(Notifications::SmsClient).to receive(:deliver) do |to:, body:|
        expect(to).to eq("+93700000001")
        expect(body).to match(/\d{4,8}/)
        Notifications::SmsClient::Result.new(delivered: true, provider: "log")
      end

      post "/api/v1/auth/otp", params: { phone: "+93700000001" }

      expect(response).to have_http_status(:ok)
    end

    it "sends the Pashto template when the app asks in Pashto" do
      Setting.find_or_initialize_by(key: "otp_sms_body_ps")
             .update!(value: "کاروان: کوډ %{code}", value_type: :string)

      expect(Notifications::SmsClient).to receive(:deliver) do |to:, body:|
        expect(body).to start_with("کاروان")
        Notifications::SmsClient::Result.new(delivered: true, provider: "log")
      end

      post "/api/v1/auth/otp", params: { phone: "+93700000002", locale: "ps" }
    end

    # A failed send must not look like a successful one to the server's own
    # logs — "nobody can log in" and "nothing happened" are different problems.
    it "logs a failed delivery rather than swallowing it" do
      allow(Notifications::SmsClient).to receive(:deliver)
        .and_return(Notifications::SmsClient::Result.new(delivered: false, provider: "log", error: "gateway down"))
      expect(Rails.logger).to receive(:error).with(/gateway down/)

      post "/api/v1/auth/otp", params: { phone: "+93700000003" }

      # Still 200: the code WAS issued and a retry may land, and telling a
      # caller which numbers fail is not information worth giving away.
      expect(response).to have_http_status(:ok)
    end
  end
end
