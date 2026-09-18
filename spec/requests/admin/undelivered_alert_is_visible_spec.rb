require "rails_helper"

# ═══ A RESTAURANT THAT NEVER HEARD THE ALERT ═══════════════════════════════
#
# CLAUDE.md: "A missed 'new order' alert is a lost order, not an annoyance."
# PRODUCT.md builds the merchant side around a tablet on a counter in a noisy
# kitchen. Push is deliberately ONE OF THREE channels — push, in-app polling,
# and a human ringing the shop — and the third is the one that has to be told.
#
# ── THE FLAG EXISTED AND NOBODY COULD SEE IT ─────────────────────────────
#
# `Notifications::MerchantAlert` has recorded `needs_human_contact: true` since
# the day it was written: unconfigured FCM, no registered tablet, every token
# dead. It was asserted in its own unit spec and **read by nothing in `app/`**.
# `details` is a show-page field on `AuditLogDashboard`, so an operator asking
# "who do I need to ring?" had to open every `merchant.alerted` row and read
# its JSON.
#
# That is the fourth instance of one shape in a day — built, correct,
# unreachable — and the most expensive, because the remedy is a telephone and
# the window is the time a customer will wait for food.
RSpec.describe "an undelivered merchant alert is visible to an operator", type: :request do
  let(:admin) do
    AdminUser.create!(name: "Najibullah", email: "ops@karwan.af", password: "a-long-test-password")
  end

  before do
    post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
  end

  let(:merchant) { create(:merchant, name: "Kabab House") }

  # Drives the REAL alert path with no FCM credentials — which is the state a
  # deployed box is in today — rather than writing an AuditLog by hand. A
  # fabricated row would prove the tile can count rows, not that this situation
  # produces one.
  def alert!(order)
    Notifications::MerchantAlert.new(order, client: Notifications::FcmClient.new(project_id: nil, access_token: nil)).deliver!
  end

  it "counts a live order whose merchant was never reached" do
    order = create(:order, :placed, merchant: merchant)
    result = alert!(order)
    expect(result.status).to eq(:no_tokens), "the alert was delivered — nothing to surface"

    get "/admin"

    expect(response.body).to include("shops to ring")
    expect(response.body).to match(/>1<.{0,200}shops to ring/m)
  end

  it "shows nothing to do when every alert reached a device" do
    owner = create(:user, :merchant_owner)
    merchant.update!(owner: owner)
    owner.device_tokens.create!(token: "a-live-tablet", platform: :android)
    order = create(:order, :placed, merchant: merchant)

    allow_any_instance_of(Notifications::FcmClient).to receive(:configured?).and_return(true)
    allow_any_instance_of(Notifications::FcmClient).to receive(:deliver_one).and_return(true)
    Notifications::MerchantAlert.new(order).deliver!

    get "/admin"

    expect(response.body).to match(/>0<.{0,200}shops to ring/m)
  end

  # A failed alert on an order that has since been delivered was resolved by
  # somebody. Counting it forever turns the tile into a number an operator
  # learns to ignore, which is the same as not having it.
  it "stops counting once the order is no longer live" do
    order = create(:order, :placed, merchant: merchant)
    alert!(order)

    get "/admin"
    expect(response.body).to match(/>1<.{0,200}shops to ring/m)

    order.update!(status: :delivered, delivered_at: Time.current)

    get "/admin"
    expect(response.body).to match(/>0<.{0,200}shops to ring/m)
  end

  it "counts each order once, however many times the alert was retried" do
    order = create(:order, :placed, merchant: merchant)
    3.times { alert!(order) }

    get "/admin"

    expect(response.body).to match(/>1<.{0,200}shops to ring/m)
  end
end
