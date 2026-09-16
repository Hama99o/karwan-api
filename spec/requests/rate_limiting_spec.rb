require "rails_helper"

# The limits themselves, and the properties that make them safe.
#
# Rate limiting is the first thing in this app to touch Rails.cache, so the
# question is not only "does it limit" but "what happens when the cache is
# gone" — a limiter that turns sign-in into a 500 during a cache outage is
# worse than no limiter.
RSpec.describe "Rate limiting", type: :request do
  def json
    JSON.parse(response.body)
  end

  # Turns the retained code flow back on, for the examples that drive it. The
  # OTP endpoint refuses with `otp_disabled` otherwise, and a 422 is not a
  # statement about the limiter.
  def enable_otp!
    Setting.find_or_initialize_by(key: "otp_sign_in_enabled")
           .update!(value: "true", value_type: :boolean)
  end

  # ── THE DOORS THAT ACTUALLY HAND OUT A SESSION TODAY ──────────────────────
  #
  # These three replaced the OTP endpoint as the live entrances when Hamma9900
  # switched to a password. The distinction matters for the limiter: an
  # unthrottled endpoint here is somebody working through a list of numbers on
  # the owner's infrastructure, and on `password_reset` it is his SMS bill.
  describe "the endpoints that hand out a session" do
    it "eventually limits SIGN-IN attempts from one address" do
      121.times { post "/api/v1/auth/session", params: { identifier: "+93700001234", password: "wrong" } }

      expect(response).to have_http_status(:too_many_requests)
      expect(json["code"]).to eq("rate_limited")
    end

    it "does not limit a normal number of sign-in attempts" do
      create(:user, phone: "+93700001234", password: "a-long-enough-password")

      5.times { post "/api/v1/auth/session", params: { identifier: "+93700001234", password: "a-long-enough-password" } }

      expect(response).to have_http_status(:created)
    end

    # Tighter than sign-in, because an account is a row AND a wallet.
    it "eventually limits REGISTRATIONS from one address" do
      31.times do |i|
        post "/api/v1/auth/registration",
             params: { phone: "+9370001#{i.to_s.rjust(4, '0')}", password: "a-long-enough-password" }
      end

      expect(response).to have_http_status(:too_many_requests)
      expect(json["code"]).to eq("rate_limited")
    end

    # THE TIGHTEST OF THE THREE, and the only one that spends money: every
    # attempt here can send an SMS. The per-phone counter inside
    # OtpVerification cannot see a script working through a list of ADDRESSES,
    # which is what this limit is for.
    it "eventually limits PASSWORD RESET requests from one address" do
      21.times { |i| post "/api/v1/auth/password_reset", params: { identifier: "someone#{i}@example.com" } }

      expect(response).to have_http_status(:too_many_requests)
      expect(json["code"]).to eq("rate_limited")
    end

    it "does not limit somebody legitimately mistyping their email twice" do
      2.times { post "/api/v1/auth/password_reset", params: { identifier: "ahmad@gmail.com" } }

      expect(response).to have_http_status(:ok)
    end
  end

  # The retained flow keeps its limits, and they keep being tested — a switched
  # off path whose protections have quietly rotted is worse than a deleted one,
  # because switching it back on looks free.
  describe "the retained OTP endpoint" do
    before { enable_otp! }

    # Keyed on IP because there is no user yet, and kept GENEROUS: mobile users
    # in Afghanistan sit behind carrier-grade NAT, so a whole neighbourhood can
    # share one address.
    it "eventually limits OTP requests from one address" do
      61.times { |i| post "/api/v1/auth/otp", params: { phone: "+9370000#{i.to_s.rjust(4, '0')}" } }

      expect(response).to have_http_status(:too_many_requests)
      expect(json["code"]).to eq("rate_limited")
    end

    it "does not limit a normal number of requests" do
      5.times { |i| post "/api/v1/auth/otp", params: { phone: "+9370000#{i.to_s.rjust(4, '0')}" } }

      expect(response).to have_http_status(:ok)
    end

    # The per-PHONE limit is the one that protects the SMS bill and it is
    # separate — this asserts the two do not interfere.
    it "still throttles per phone independently of the IP limit" do
      4.times { post "/api/v1/auth/otp", params: { phone: "+93700009999" } }

      expect(response).to have_http_status(:too_many_requests)
      expect(json["code"]).to eq("otp_throttled")
    end

    # THE LIMIT STILL APPLIES WHILE THE FLOW IS OFF. `throttle` runs as a
    # before_action, ahead of the refusal — so a script hammering a disabled
    # endpoint is still capped rather than handed a free 422 loop.
    it "limits the endpoint even when the flow is switched off" do
      Setting.find_by(key: "otp_sign_in_enabled").update!(value: "false")

      61.times { |i| post "/api/v1/auth/otp", params: { phone: "+9370000#{i.to_s.rjust(4, '0')}" } }

      expect(response).to have_http_status(:too_many_requests)
    end
  end

  describe "endpoints behind authentication" do
    let(:customer) { create(:user, :customer) }
    let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(customer).last}" } }
    let(:merchant) { create(:merchant, latitude: 34.5553, longitude: 69.2075) }
    let!(:item) { create(:catalog_item, catalog_category: create(:catalog_category, merchant: merchant)) }

    def place
      post "/api/v1/customer/orders",
           params: { order: { merchant_id: merchant.id, delivery_latitude: 34.54,
                              delivery_longitude: 69.175,
                              lines: [ { catalog_item_id: item.id, quantity: 1 } ] } },
           headers: auth
    end

    it "limits order placement per USER, far above real use" do
      41.times { place }

      expect(response).to have_http_status(:too_many_requests)
    end

    # One abusive account must not spend anyone else's quota. This is the whole
    # reason authenticated endpoints key on the user rather than the IP.
    it "does not let one account's limit affect another's" do
      41.times { place }
      expect(response).to have_http_status(:too_many_requests)

      other = create(:user, :customer)
      post "/api/v1/customer/orders",
           params: { order: { merchant_id: merchant.id, delivery_latitude: 34.54,
                              delivery_longitude: 69.175,
                              lines: [ { catalog_item_id: item.id, quantity: 1 } ] } },
           headers: { "Authorization" => "Bearer #{UserSession.issue!(other).last}" }

      expect(response).to have_http_status(:created)
    end

    it "does not limit a realistic number of orders" do
      3.times { place }

      expect(response).to have_http_status(:created)
    end
  end

  describe "browsing" do
    # Correction 10: a first-time user must reach a merchant before being asked
    # for anything, so browsing must never be the thing that locks them out.
    # The limit sits where only a script would reach it.
    it "does not limit a customer moving around the app" do
      create(:merchant)

      50.times { get "/api/v1/public/merchants" }

      expect(response).to have_http_status(:ok)
    end
  end

  describe "safety properties" do
    # THE IMPORTANT ONE, and now asserted on THE LIVE SIGN-IN rather than on the
    # disabled code endpoint. That is what this example always meant — the
    # header of this file says "a limiter that turns sign-in into a 500 during a
    # cache outage is worse than no limiter" — and it was quietly testing a door
    # nobody walks through any more. Losing a limit for the duration of an
    # outage is far cheaper than losing the endpoint.
    it "FAILS OPEN when the cache store is broken" do
      create(:user, phone: "+93700001234", password: "a-long-enough-password")
      allow(RateLimitable.store).to receive(:increment).and_raise(Redis::CannotConnectError) if defined?(Redis)
      allow(RateLimitable.store).to receive(:increment).and_raise(StandardError, "cache is gone")

      post "/api/v1/auth/session", params: { identifier: "+93700001234", password: "a-long-enough-password" }

      expect(response).to have_http_status(:created)
    end

    it "reports the failure rather than swallowing it" do
      create(:user, phone: "+93700001234", password: "a-long-enough-password")
      allow(RateLimitable.store).to receive(:increment).and_raise(StandardError, "cache is gone")
      expect(Rails.error).to receive(:report).at_least(:once).and_call_original

      post "/api/v1/auth/session", params: { identifier: "+93700001234", password: "a-long-enough-password" }

      expect(response).to have_http_status(:created)
    end

    # The test environment defaults to :null_store, whose increment always
    # returns nil — which would make every limit a silent no-op AND impossible
    # to test. That is the vacuously-green trap this project has hit four times,
    # so the store is asserted to be a real one.
    it "uses a store that can actually count in tests" do
      expect(RateLimitable.store).to be_a(ActiveSupport::Cache::MemoryStore)

      RateLimitable.store.write("probe", 0, raw: true)
      expect(RateLimitable.store.increment("probe")).to eq(1)
    end

    it "refuses a throttle declared on something other than :ip or :user" do
      expect { Class.new(ApplicationController) { throttle to: 1, within: 1.hour, by: :nonsense } }
        .to raise_error(ArgumentError, /:ip or :user/)
    end
  end
end
