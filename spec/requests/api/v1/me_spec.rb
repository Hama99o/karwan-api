require "rails_helper"

RSpec.describe "Api::V1::Me", type: :request do
  def json
    JSON.parse(response.body)
  end

  let(:user) { create(:user, :customer, name: "احمد کریمی") }
  let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(user).last}" } }

  describe "GET /api/v1/me" do
    it "returns who they are and which roles they hold" do
      get "/api/v1/me", headers: auth

      expect(response).to have_http_status(:ok)
      expect(json.dig("user", "phone")).to eq(user.phone)
      expect(json.dig("user", "roles")).to eq([ "customer" ])
      expect(json.dig("user", "can_switch_roles")).to be false
    end

    it "refuses without a token" do
      get "/api/v1/me"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/me/switch_role" do
    # ONE ACCOUNT, SEVERAL ROLES. Stored server-side rather than only on the
    # device, so a reinstall does not drop a courier back into the customer tab.
    it "switches to a role the person holds" do
      user.user_roles.create!(role: :courier)

      post "/api/v1/me/switch_role", params: { role: "courier" }, headers: auth

      expect(response).to have_http_status(:ok)
      expect(user.reload.active_role).to eq("courier")
      expect(json.dig("user", "can_switch_roles")).to be true
    end

    # Returns a 422 with a code rather than raising, so a stale client cannot
    # 500 this — and the app renders its own Pashto message from the code.
    it "refuses a role they do not hold" do
      post "/api/v1/me/switch_role", params: { role: "admin" }, headers: auth

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("role_not_held")
      expect(user.reload.active_role).to eq("customer")
    end

    it "refuses a role that does not exist" do
      post "/api/v1/me/switch_role", params: { role: "wizard" }, headers: auth

      expect(json["code"]).to eq("role_not_held")
    end
  end

  # WITHOUT THIS THE MERCHANT ALERT HAS NOTHING TO DELIVER TO. The model and
  # the sender existed before any way for a phone to report its token, which
  # made the whole alert chain untestable end to end.
  describe "POST /api/v1/me/register_device" do
    it "registers a push token" do
      post "/api/v1/me/register_device",
           params: { token: "ExponentPushToken[abc]", platform: "android" }, headers: auth

      expect(response).to have_http_status(:ok)
      expect(user.device_tokens.active.pluck(:token)).to eq([ "ExponentPushToken[abc]" ])
    end

    # The app re-registers on every launch; a unique-constraint error here
    # would break the launch rather than the push.
    it "is idempotent across relaunches" do
      2.times do
        post "/api/v1/me/register_device", params: { token: "same", platform: "android" }, headers: auth
      end

      expect(DeviceToken.where(token: "same").count).to eq(1)
    end

    # A merchant tablet gets handed between staff, and the alert must not keep
    # going to somebody who went home.
    it "moves a token to whoever is signed in now" do
      other = create(:user, :merchant_owner)
      DeviceToken.register!(user: other, token: "tablet", platform: :android)

      post "/api/v1/me/register_device", params: { token: "tablet", platform: "android" }, headers: auth

      expect(DeviceToken.find_by!(token: "tablet").user_id).to eq(user.id)
      expect(DeviceToken.where(token: "tablet").count).to eq(1)
    end

    it "refuses an unknown platform" do
      post "/api/v1/me/register_device", params: { token: "x", platform: "blackberry" }, headers: auth

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("bad_platform")
    end

    it "refuses without a token header" do
      post "/api/v1/me/register_device", params: { token: "x" }

      expect(response).to have_http_status(:unauthorized)
    end

    # Phones are shared (AFGHAN_UX §7), so signing out must stop the next
    # person receiving this person's orders.
    it "deactivates on sign-out from a shared phone" do
      post "/api/v1/me/register_device", params: { token: "shared" }, headers: auth

      delete "/api/v1/me/unregister_device", params: { token: "shared" }, headers: auth

      expect(response).to have_http_status(:no_content)
      expect(user.device_tokens.active).to be_empty
      # Deactivated, not deleted — re-registering the same handset works.
      expect(DeviceToken.find_by(token: "shared")).to be_present
    end
  end

  # The chain that was broken: a token registered here must actually reach the
  # merchant alert.
  describe "the alert chain, end to end" do
    it "delivers a new-order alert to a token the app registered" do
      owner = create(:user, :merchant_owner)
      merchant = create(:merchant, owner: owner)
      owner_auth = { "Authorization" => "Bearer #{UserSession.issue!(owner).last}" }

      post "/api/v1/me/register_device",
           params: { token: "kitchen-tablet", platform: "android" }, headers: owner_auth

      order = create(:order, :with_items, merchant: merchant)
      result = Notifications::MerchantAlert.new(order).deliver!

      # Unconfigured because no FCM credentials are wired — but it FOUND the
      # device, which is what was impossible before this endpoint existed.
      expect(result.status).to eq(:unconfigured)
      log = AuditLog.where(action: "merchant.alerted", target: order).last
      expect(log.details["devices"]).to eq(1)
    end
  end
end
