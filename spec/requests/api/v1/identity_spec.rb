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
#   2. current_role ignores a client-supplied role            → BELOW
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

  # ── §9.2, TESTED AT THE METHOD, BECAUSE NO ENDPOINT CAN TEST IT ───────────
  #
  # The three examples above assert the OUTCOME: nothing the client sends
  # changes what the app is told. They do not test `current_role`, and I found
  # that out by planting the bug — I rewrote `current_role` to read
  # `params[:role]` and `X-Role` first, and all twelve examples stayed green.
  #
  # The reason is that **`current_role` has no callers.** The role namespaces
  # and the Pundit scopes read `user_roles` directly, so the method is a
  # contract waiting for its first consumer. That is exactly the kind of
  # not-quite-dead code that gets used in six months by somebody who assumes
  # it was tested.
  #
  # So it is tested directly, and the probe is the test: it includes the concern
  # and defines NEITHER `params` NOR `request`. Any implementation that reaches
  # for the request raises `NoMethodError` here. The rule is not "prefer the
  # session" — it is "the request is not an input to this question at all".
  describe "Authenticatable#current_role, at the method" do
    let(:probe_class) do
      Class.new do
        include Authenticatable
        public :current_role

        def initialize(session)
          @current_session = session
          @current_user = session&.user
        end
      end
    end

    it "reads the session's role" do
      user = create(:user, :courier)
      session, = UserSession.issue!(user, requested_role: "courier")

      expect(probe_class.new(session).current_role).to eq("courier")
    end

    # Not the user's preference either: two devices, two roles, and the
    # preference is only what seeds a new one.
    it "does not read the user's last chosen role" do
      user = create(:user, :courier)
      session, = UserSession.issue!(user, requested_role: "courier")
      user.update!(last_active_role: :customer)

      expect(probe_class.new(session).current_role).to eq("courier")
    end

    it "cannot consult params or headers, because it has none to consult" do
      probe = probe_class.new(UserSession.issue!(create(:user, :customer)).first)

      expect(probe).not_to respond_to(:params)
      expect { probe.current_role }.not_to raise_error
    end

    it "is nil for a signed-out request rather than guessing customer" do
      expect(probe_class.new(nil).current_role).to be_nil
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
