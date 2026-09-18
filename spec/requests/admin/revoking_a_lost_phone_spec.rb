require "rails_helper"

# ═══ A COURIER'S PHONE HAS BEEN LOST ═══════════════════════════════════════
#
# This is a security action, not tidiness. In a cash business, whoever holds a
# courier's phone can go on shift as that courier, accept offers and collect our
# money — and the wallet's credit line means they can do it before anybody
# notices. `UserSession#revoke!` existed and **nothing called it from the
# console**, so the only remedy was a Rails console.
#
# ── REVOKE, NEVER DISPLAY ────────────────────────────────────────────────
#
# `user_sessions.token_digest` and `device_tokens.token` are credentials. A
# console that prints either is a console that leaks a working session or a push
# target — so the operator gets a COUNT and a DATE, which is the whole
# operational question, and never a value.
RSpec.describe "revoking a lost phone's sessions", type: :request do
  let(:admin) do
    AdminUser.create!(name: "Najibullah", email: "ops@karwan.af", password: "a-long-test-password")
  end

  before do
    post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
  end

  let(:courier) { create(:user, :courier, name: "Ahmad") }

  it "revokes every live session, and the phone stops working" do
    token = UserSession.issue!(courier).last
    get "/api/v1/me", headers: { "Authorization" => "Bearer #{token}" }
    expect(response).to have_http_status(:ok), "the token did not work to begin with"

    patch "/admin/users/#{courier.id}/revoke_sessions"

    get "/api/v1/me", headers: { "Authorization" => "Bearer #{token}" }
    expect(response).to have_http_status(:unauthorized)
  end

  it "names the admin who did it, and how many were live" do
    2.times { UserSession.issue!(courier) }

    expect {
      patch "/admin/users/#{courier.id}/revoke_sessions"
    }.to change(AuditLog, :count).by(1)

    log = AuditLog.newest_first.first
    expect(log.action).to eq("user.sessions_revoked")
    expect(log.admin_user_id).to eq(admin.id)
    expect(log.before.to_s).to include("2")
  end

  it "revokes nobody else's" do
    other = create(:user, :courier)
    others_token = UserSession.issue!(other).last
    UserSession.issue!(courier)

    patch "/admin/users/#{courier.id}/revoke_sessions"

    get "/api/v1/me", headers: { "Authorization" => "Bearer #{others_token}" }
    expect(response).to have_http_status(:ok)
  end

  it "is not an error when there is nothing to revoke" do
    patch "/admin/users/#{courier.id}/revoke_sessions"

    expect(response).to have_http_status(:redirect)
  end

  describe "what the operator can see" do
    it "counts live sessions without showing a single token" do
      UserSession.issue!(courier)
      digest = UserSession.live.first.token_digest

      get "/admin/users/#{courier.id}"

      expect(response.body).to match(/live session/i)
      expect(response.body).not_to include(digest),
                                  "the console is printing a session credential"
    end

    # The first question when a merchant's board stayed silent, and it pairs
    # with the landing page's "shops to ring" count.
    it "says whether a device is registered at all, without showing the token" do
      get "/admin/users/#{courier.id}"
      expect(response.body).to include("none registered")

      courier.device_tokens.create!(token: "a-real-push-token", platform: :android)

      get "/admin/users/#{courier.id}"
      expect(response.body).to match(/1 active \(android\)/)
      expect(response.body).not_to include("a-real-push-token"),
                                  "the console is printing a push token"
    end
  end
end
