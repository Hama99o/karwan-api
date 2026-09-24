require "rails_helper"

# ═══ THE CONSOLE'S STYLESHEET REACHES THE BROWSER ═════════════════════════
#
# `app/assets/stylesheets/karwan_admin.css` carries the board's staleness
# colours — an order stuck too long *"turns red... visible from across a
# room"* — and nothing had ever registered it with Administrate. Measured in a
# real browser on the dev board, 24 Sept 2026: **50 `karwan-row--alert` rows,
# computed background `rgba(0, 0, 0, 0)`**. After registering it, the same 50
# computed `rgb(253, 236, 234)`.
#
# `console_spec` asserts the CLASS NAME is in the HTML, which is true whether
# or not any rule for it reaches a browser. So this follows the page's own
# `<link rel=stylesheet>` tags and reads what they serve.
RSpec.describe "the console stylesheet is served", type: :request do
  let(:admin) { AdminUser.create!(name: "Ops", email: "ops@karwan.af", password: "a-long-test-password") }

  it "is linked from a console page and serves the rule that turns a stuck order red" do
    post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
    get "/admin/orders"
    expect(response).to have_http_status(:ok)

    hrefs = Nokogiri::HTML(response.body).css("link[rel=stylesheet]").map { |l| l["href"] }
    ours = hrefs.grep(/karwan_admin/)
    expect(ours).not_to be_empty, "no karwan_admin stylesheet linked; linked: #{hrefs.inspect}"

    get URI(ours.first).path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(".karwan-row--alert").and include(".karwan-actions")
  end
end
