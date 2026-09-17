require "rails_helper"

RSpec.describe "Api::V1::Me", type: :request do
  def json
    JSON.parse(response.body)
  end

  let(:user) { create(:user, :customer, name: "احمد کریمی") }
  let(:phone_session) { UserSession.issue!(user, device_name: "his phone") }
  let(:auth) { { "Authorization" => "Bearer #{phone_session.last}" } }

  describe "GET /api/v1/me" do
    it "returns who they are and which roles they hold" do
      get "/api/v1/me", headers: auth

      expect(response).to have_http_status(:ok)
      expect(json.dig("user", "phone")).to eq(user.phone)
      # Which mode THIS device is in, which is what the app opens on.
      expect(json.dig("user", "active_role")).to eq("customer")
      expect(json.dig("user", "roles")).to eq([ "customer" ])
      expect(json.dig("user", "can_switch_roles")).to be false
    end

    it "refuses without a token" do
      get "/api/v1/me"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ── EDITING YOUR OWN RECORD, WHICH HAD NEVER WORKED ───────────────────────
  #
  # `update` has called a `profile_params` that did not exist since it was
  # written, so this endpoint answered 500 with `undefined local variable or
  # method 'profile_params'` for its whole life. No request spec covered it,
  # which is why nothing said so. Found while building the Profile screen —
  # its first caller.
  describe "PATCH /api/v1/me" do
    it "changes the name" do
      patch "/api/v1/me", params: { name: "احمد شاه" }, headers: auth

      expect(response).to have_http_status(:ok)
      expect(json.dig("user", "name")).to eq("احمد شاه")
      expect(user.reload.name).to eq("احمد شاه")
    end

    # AFGHAN_UX.md §8 wants the language remembered per PERSON rather than per
    # device, precisely because phones are shared — so this belongs on the user
    # row and not only in the app's storage.
    it "changes the language, because a shared phone is not one person" do
      patch "/api/v1/me", params: { locale: "fa" }, headers: auth

      expect(user.reload.locale).to eq("fa")
    end

    it "refuses a language the app does not have" do
      patch "/api/v1/me", params: { locale: "de" }, headers: auth

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.locale).not_to eq("de")
    end

    # ── THE PHONE IS THE IDENTITY AND MAY NOT BE EDITED HERE ────────────────
    #
    # NOT NULL, unique, normalised, and the number a courier rings from outside
    # the gate. Changing it is an identity change and needs a verification step
    # this platform deliberately does not have.
    it "IGNORES an attempt to change the phone" do
      patch "/api/v1/me", params: { name: "احمد شاه", phone: "+93700009999" }, headers: auth

      expect(response).to have_http_status(:ok)
      # The permitted field still applied — a filtered param is not an error.
      expect(user.reload.name).to eq("احمد شاه")
      expect(user.phone).not_to eq("+93700009999")
    end

    # ── AND THE EMAIL, WHICH IS THE LESS OBVIOUS ONE ────────────────────────
    #
    # It is also a PASSWORD RESET CHANNEL. With no verification step, a session
    # that could add an address would let somebody holding a borrowed phone add
    # their own and then reset the password — and AFGHAN_UX.md §7 says shared
    # handsets are normal here, not hypothetical.
    it "IGNORES an attempt to add or change the email" do
      patch "/api/v1/me", params: { email: "attacker@example.com" }, headers: auth

      expect(response).to have_http_status(:ok)
      expect(user.reload.email).not_to eq("attacker@example.com")
    end

    it "does not let anyone change somebody else's record" do
      other = create(:user, :customer, name: "بل سوک")

      patch "/api/v1/me", params: { name: "Changed" }, headers: auth

      expect(other.reload.name).to eq("بل سوک")
    end

    it "refuses without a token" do
      patch "/api/v1/me", params: { name: "Nobody" }

      expect(response).to have_http_status(:unauthorized)
    end

    # An empty body is a no-op rather than a 400: nothing here is destructive,
    # and a client that sends only the field it changed should not have to wrap
    # it in a root key.
    it "tolerates a body with nothing in it" do
      patch "/api/v1/me", params: {}, headers: auth

      expect(response).to have_http_status(:ok)
      expect(user.reload.name).to eq("احمد کریمی")
    end
  end

  describe "POST /api/v1/me/switch_role" do
    # ONE ACCOUNT, SEVERAL ROLES, ONE DEVICE AT A TIME.
    it "switches to a role the person holds" do
      user.user_roles.create!(role: :courier)

      post "/api/v1/me/switch_role", params: { role: "courier" }, headers: auth

      expect(response).to have_http_status(:ok)
      expect(phone_session.first.reload.active_role).to eq("courier")
      expect(json.dig("user", "active_role")).to eq("courier")
      expect(json.dig("user", "can_switch_roles")).to be true
    end

    # THE REASON THIS MOVED OFF `users`. A merchant keeps a tablet on the
    # counter and a phone in his pocket. Flipping the phone to the customer tab
    # used to flip the tablet's next launch too — one account, one shared hat.
    it "does not change the mode of his OTHER device" do
      user.user_roles.create!(role: :merchant_owner)
      tablet, tablet_token = UserSession.issue!(user, device_name: "counter tablet")
      tablet.switch_role!(:merchant_owner)

      post "/api/v1/me/switch_role", params: { role: "customer" }, headers: auth

      expect(tablet.reload.active_role).to eq("merchant_owner")
      get "/api/v1/me", headers: { "Authorization" => "Bearer #{tablet_token}" }
      expect(json.dig("user", "active_role")).to eq("merchant_owner")
    end

    # And it is still remembered across a reinstall, which is what the column
    # on `users` is now for: a new session is not a fresh start.
    it "is remembered by the NEXT device the person signs in on" do
      user.user_roles.create!(role: :courier)

      post "/api/v1/me/switch_role", params: { role: "courier" }, headers: auth
      _reinstalled, new_token = UserSession.issue!(user.reload, device_name: "same phone, reinstalled")

      get "/api/v1/me", headers: { "Authorization" => "Bearer #{new_token}" }
      expect(json.dig("user", "active_role")).to eq("courier")
    end

    # Returns a 422 with a code rather than raising, so a stale client cannot
    # 500 this — and the app renders its own Pashto message from the code.
    it "refuses a role they do not hold" do
      post "/api/v1/me/switch_role", params: { role: "admin" }, headers: auth

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("role_not_held")
      expect(phone_session.first.reload.active_role).to eq("customer")
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
