require "rails_helper"

# ═══ A SHARED PHONE MUST NOT REACH THE WALLET BY TAPPING ═══════════════════
#
# `IDENTITY_AND_ROLES.md` §7: *"Switching into a money-handling role mid-session
# needs re-authentication, because the wallet, the top-up code and 'close the
# restaurant' are the most damaging things a stranger holding an unlocked phone
# can reach."* `CLAUDE.md` correction 18 settles it from the other end — the
# sign-in choice is the gate for ENTERING a role, and a switch inside a live
# session had never passed that gate.
#
# `AFGHAN_UX.md` §7 is why it is not hypothetical: *"A phone in a household may
# be used by several people."* The threat is a cousin with an unlocked handset,
# not a thief with tools.
RSpec.describe "switching into a money-handling role", type: :request do
  def json
    JSON.parse(response.body)
  end

  let(:password) { "a-long-real-password" }
  let(:user) { create(:user, :customer, password: password) }
  let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(user).last}" } }

  before do
    user.grant_role!(:courier)
    user.grant_role!(:merchant_owner)
  end

  Roles::MONEY_HANDLING.each do |role|
    it "refuses a switch into #{role} with no password" do
      post "/api/v1/me/switch_role", params: { role: role }, headers: auth

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("reauthentication_required")
    end

    it "refuses a switch into #{role} with the wrong password" do
      post "/api/v1/me/switch_role", params: { role: role, password: "not-it" }, headers: auth

      expect(json["code"]).to eq("reauthentication_required")
    end

    it "allows a switch into #{role} with the password" do
      post "/api/v1/me/switch_role", params: { role: role, password: password }, headers: auth

      expect(response).to have_http_status(:ok)
      expect(json.dig("user", "active_role")).to eq(role)
    end
  end

  # ── THE ASYMMETRY IS THE DESIGN ───────────────────────────────────────────
  #
  # The gate is on reaching the money, not on leaving it. Asking for a password
  # to go back to ordering a kebab is exactly the friction correction 10 spends
  # its whole argument removing.
  it "lets a courier drop back to customer without asking for anything" do
    post "/api/v1/me/switch_role", params: { role: "courier", password: password }, headers: auth
    expect(json.dig("user", "active_role")).to eq("courier")

    post "/api/v1/me/switch_role", params: { role: "customer" }, headers: auth

    expect(response).to have_http_status(:ok)
    expect(json.dig("user", "active_role")).to eq("customer")
  end

  # AN ABSENT PASSWORD AND A WRONG ONE GIVE THE SAME ANSWER — the oracle rule
  # this API already holds for sign-in. Telling them apart tells an attacker
  # which half of the problem to work on.
  it "does not distinguish a missing password from a wrong one" do
    post "/api/v1/me/switch_role", params: { role: "courier" }, headers: auth
    absent = [ response.status, json["code"], json["error"] ]

    post "/api/v1/me/switch_role", params: { role: "courier", password: "not-it" }, headers: auth
    wrong = [ response.status, json["code"], json["error"] ]

    expect(absent).to eq(wrong)
  end

  # THE ROLE CHECK STILL COMES AFTER. A correct password does not conjure a role
  # the person does not hold.
  it "still refuses a role the user does not hold, password or not" do
    stranger = create(:user, :customer, password: password)
    headers = { "Authorization" => "Bearer #{UserSession.issue!(stranger).last}" }

    post "/api/v1/me/switch_role", params: { role: "courier", password: password }, headers: headers

    expect(json["code"]).to eq("role_not_held")
  end

  # The session is what carries the role, so a refusal must leave it untouched —
  # not half-switched, which is the state that shows a courier screen to a
  # customer session.
  it "leaves the session's role alone when it refuses" do
    session = UserSession.issue!(user)
    before_role = session.first.active_role

    post "/api/v1/me/switch_role", params: { role: "courier" },
                                   headers: { "Authorization" => "Bearer #{session.last}" }

    expect(session.first.reload.active_role).to eq(before_role)
  end
end
