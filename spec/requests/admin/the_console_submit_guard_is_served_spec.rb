require "rails_helper"

# ═══ ONE PRESS, ONE REQUEST — THE GUARD REACHES THE BROWSER ═══════════════
#
# Every intervention form here is `data: { turbo: false }`, and Administrate
# 1.0 ships no rails-ujs, so `data-disable-with` and `data-confirm` had no
# reader: a double click on "Top up" credited a courier twice, and nine
# confirm prompts had never been shown. `app/assets/javascripts/karwan_admin.js`
# is the reader. Its behaviour was checked in Chromium against this page's
# real markup (24 Sept 2026); this spec holds the part that can silently stop
# being true — the page linking it, and the asset serving it — the same shape
# the stylesheet was missing for weeks.
RSpec.describe "the console submit guard is served", type: :request do
  let(:admin) { AdminUser.create!(name: "Ops", email: "ops@karwan.af", password: "a-long-test-password") }
  let(:wallet) { create(:user, :courier).courier_wallet }

  before do
    post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
    get "/admin/courier_wallets/#{wallet.id}"
  end

  let(:page) { Nokogiri::HTML(response.body) }

  it "is linked from the page that moves money, and serves the guard" do
    srcs = page.css("script[src]").map { |s| s["src"] }
    ours = srcs.grep(/karwan_admin/)
    expect(ours).not_to be_empty, "no karwan_admin script linked; linked: #{srcs.inspect}"

    get URI(ours.first).path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("data-karwan-submitting").and include("window.confirm").and include("pageshow")
  end

  # The guard is scoped to native forms, so a money form that stopped being
  # one would silently fall outside it — and back under Turbo, whose own
  # disabling is what `turbo: false` switched off in the first place.
  it "covers all four money forms" do
    actions = page.css('form[data-turbo="false"]').map { |f| URI(f["action"]).path.split("/").last }

    expect(actions).to include("top_up", "adjust", "reimburse", "settle")
  end
end
