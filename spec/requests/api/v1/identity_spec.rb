require "rails_helper"

# THE RULES FROM `docs/IDENTITY_AND_ROLES.md` §9, which is binding.
#
# That file lists nine tests that must exist and must be provable red. Most
# already live where they belong, and duplicating them here would give two
# places to change and one of them would rot. So this file holds the three that
# had no home, and the map below says where the others are — the map is the
# point, because a checklist nobody can locate is a checklist nobody checks.
#
#   1. customer-only is refused every partner role
#        switch   → spec/models/user_session_spec.rb, and below
#        endpoint → spec/requests/api/v1/merchants/orders_spec.rb ("no_merchant"),
#                   spec/requests/api/v1/couriers/wallet_spec.rb ("no_courier_profile"),
#                   and below, for both in one place
#   2. the role never comes from the client                   → BELOW
#      (`current_role` and `require_role!` are DELETED — they had no callers;
#       see Authenticatable's header for what enforces this instead)
#   3. granting a partner role also yields customer           → spec/models/user_spec.rb
#   4. assigning a merchant owner grants, unassigning revokes → spec/models/merchant_ownership_spec.rb
#                                                               spec/requests/admin/merchant_owner_spec.rb
#   5. two sessions hold two active roles at once             → spec/models/user_session_spec.rb
#   6. switching one session does not change another          → spec/requests/api/v1/me_spec.rb
#   7. one live job per courier, at offer AND accept          → spec/services/dispatch/one_job_at_a_time_spec.rb
#                                                               spec/requests/api/v1/couriers/offers_spec.rb
#   8. a suspended user's valid token stops working           → BELOW
#   9. an unheld partner role returns the application path    → spec/requests/api/v1/auth/sessions_spec.rb
RSpec.describe "Identity and roles", type: :request do
  def json
    JSON.parse(response.body)
  end

  # ── §9.2 — THE ROLE NEVER COMES FROM THE CLIENT ────────────────────────────
  #
  # Four roles in one app is exactly the shape where a client-supplied role
  # becomes privilege escalation, and edu-safi shipped five endpoints where the
  # correct scope existed and was never consulted.
  describe "a role supplied by the client" do
    let(:customer) { create(:user, :customer) }
    let(:session_and_token) { UserSession.issue!(customer) }
    let(:auth) { { "Authorization" => "Bearer #{session_and_token.last}" } }

    it "is ignored as a query parameter" do
      get "/api/v1/me?role=merchant_owner", headers: auth

      expect(json.dig("user", "active_role")).to eq("customer")
    end

    it "is ignored in the body" do
      get "/api/v1/me", params: { role: "courier", active_role: "courier" }, headers: auth

      expect(json.dig("user", "active_role")).to eq("customer")
    end

    it "is ignored as a header" do
      get "/api/v1/me", headers: auth.merge("X-Role" => "admin", "X-Active-Role" => "admin")

      expect(json.dig("user", "active_role")).to eq("customer")
    end

    # And it buys nothing: the role-gated endpoints refuse whatever was sent,
    # because they read the user's own `user_roles`.
    it "does not open a partner endpoint" do
      get "/api/v1/merchant/orders?role=merchant_owner", headers: auth
      expect(response).to have_http_status(:forbidden)

      get "/api/v1/courier/job", params: { role: "courier" }, headers: auth
      expect(response).to have_http_status(:forbidden)
    end
  end

  # ── §9.2, TESTED WHERE IT IS ENFORCED, WHICH IS NOT WHERE IT WAS WRITTEN ──
  #
  # The examples above assert the OUTCOME. They do not test `current_role`, and
  # I found that out by planting the bug: I rewrote `current_role` to read
  # `params[:role]` and `X-Role` first, and every example stayed green.
  #
  # The reason was that **`current_role` had no callers** — nor did
  # `require_role!` beside it. Two methods that read as the role gate, doing
  # nothing. They are deleted; the audit that justified deleting them is in
  # `Authenticatable`'s header, and what actually enforces role access is
  # below: the policy helpers and scopes read `user_roles`, and
  # `verify_authorized` makes forgetting to call a policy raise.
  describe "what actually enforces role access" do
    let(:courier) { create(:user, :courier) }
    let(:customer) { create(:user, :customer) }

    it "reads the role from the user's own rows, in the policy" do
      expect(ApplicationPolicy.new(courier, nil)).to be_courier
      expect(ApplicationPolicy.new(customer, nil)).not_to be_courier
      expect(ApplicationPolicy.new(nil, nil)).not_to be_courier
    end

    # The scopes are the half that leaks quietly if it is wrong: a missing
    # predicate is a 403 somebody notices, a missing scope is another courier's
    # jobs on the screen.
    it "resolves nothing for a scope when the role row is absent" do
      order = create(:order, courier: courier)

      expect(OrderPolicy::CourierScope.new(courier, Order).resolve).to include(order)

      courier.revoke_role!(:courier)
      expect(OrderPolicy::CourierScope.new(courier.reload, Order).resolve).to be_empty
    end

    # ── THE MODE IS NOT A PERMISSION, AND THIS MUST STAY TRUE ────────────────
    #
    # `active_role` is which TAB a device is showing. Gating capability on it
    # is the obvious-looking "fix" that would break the two-phone setup
    # IDENTITY_AND_ROLES.md §6 requires: a courier watching rides on one phone
    # and deliveries on the other, or one whose phone died and who signed in on
    # a spare, must still be able to work the job he is carrying.
    it "lets a courier work while his device is in the customer tab" do
      courier.courier_profile.update!(is_available: true)
      session, token = UserSession.issue!(courier, requested_role: "customer")

      get "/api/v1/courier/job", headers: { "Authorization" => "Bearer #{token}" }

      expect(session.active_role).to eq("customer")
      expect(response).to have_http_status(:ok)
    end

    # And the reverse: a session sitting in the courier tab buys nothing for
    # somebody who is not a courier. The tab is a preference on both sides.
    it "gives a customer nothing for having a session in a partner tab" do
      session, = UserSession.issue!(customer)
      session.update_column(:active_role, UserSession.active_roles[:courier])

      auth = { "Authorization" => "Bearer #{UserSession.issue!(customer).last}" }
      get "/api/v1/courier/job", headers: auth

      expect(response).to have_http_status(:forbidden)
    end
  end

  # ── §9.1 — CUSTOMER → PARTNER IS NEVER AUTOMATIC ──────────────────────────
  #
  # "When we create client, we can't give access to create account as rider."
  # Both halves in one place: the switch and the endpoint.
  describe "a person holding only the customer role" do
    let(:customer) { create(:user, :customer) }

    it "cannot switch a session into any partner role" do
      session, = UserSession.issue!(customer)

      expect(session.switch_role!(:courier)).to be false
      expect(session.switch_role!(:merchant_owner)).to be false
      expect(session.switch_role!(:admin)).to be false
      expect(session.reload.active_role).to eq("customer")
    end

    it "cannot open a session in a partner role at sign-in either" do
      session, = UserSession.issue!(customer, requested_role: "courier")

      expect(session.active_role).to eq("customer")
    end

    it "is refused by every partner endpoint" do
      auth = { "Authorization" => "Bearer #{UserSession.issue!(customer).last}" }

      get "/api/v1/merchant/orders", headers: auth
      expect(response).to have_http_status(:forbidden)
      expect(json["code"]).to eq("no_merchant")

      get "/api/v1/courier/job", headers: auth
      expect(response).to have_http_status(:forbidden)
      expect(json["code"]).to eq("no_courier_profile")
    end

    # ...and can still do everything a customer does, which is the other half
    # of the asymmetry and the thing that would break silently.
    it "can still browse and read its own profile" do
      auth = { "Authorization" => "Bearer #{UserSession.issue!(customer).last}" }

      get "/api/v1/me", headers: auth
      expect(response).to have_http_status(:ok)

      get "/api/v1/public/merchants"
      expect(response).to have_http_status(:ok)
    end
  end

  # ── §9.8 — A SUSPENDED ACCOUNT STOPS WORKING IMMEDIATELY ──────────────────
  #
  # Suspension is the only lever against a courier who has taken our cash, and
  # a 90-day token means "we will stop them at the next login" is not an
  # answer. One human, one account, suspended everywhere.
  describe "a suspended account" do
    it "stops working mid-session, on a token that was valid a moment ago" do
      courier = create(:user, :courier)
      auth = { "Authorization" => "Bearer #{UserSession.issue!(courier).last}" }

      get "/api/v1/me", headers: auth
      expect(response).to have_http_status(:ok)

      courier.update!(status: :suspended)

      get "/api/v1/me", headers: auth
      expect(response).to have_http_status(:unauthorized)
      expect(json["code"]).to eq("unauthorized")
    end

    it "stops working on the courier's own endpoints too, not only on /me" do
      courier = create(:user, :courier)
      auth = { "Authorization" => "Bearer #{UserSession.issue!(courier).last}" }
      courier.update!(status: :suspended)

      get "/api/v1/courier/job", headers: auth

      expect(response).to have_http_status(:unauthorized)
    end

    # A deleted account is the same answer. `kept?` is checked beside the
    # status, and a soft-deleted person holding a live token is exactly the
    # case a `default_scope` would have hidden.
    it "refuses a soft-deleted account holding a live token" do
      user = create(:user, :customer)
      auth = { "Authorization" => "Bearer #{UserSession.issue!(user).last}" }
      user.discard!

      get "/api/v1/me", headers: auth

      expect(response).to have_http_status(:unauthorized)
    end

    it "lets them back in once they are reinstated" do
      user = create(:user, :customer)
      auth = { "Authorization" => "Bearer #{UserSession.issue!(user).last}" }
      user.update!(status: :suspended)
      user.update!(status: :active)

      get "/api/v1/me", headers: auth

      expect(response).to have_http_status(:ok)
    end
  end
end
