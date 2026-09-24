require "rails_helper"

# ═══ A JOB THAT ALREADY HAS A COURIER IS NEVER OFFERED ═════════════════════
#
# `Admin::OrdersController#redispatch` says what it is for: *"Re-runs dispatch
# by hand for an order nobody took."* Nothing enforced the "nobody took". Neither
# `Dispatch::OfferService` nor `Dispatch::Eligibility` asked whether the job
# already had a courier — every check was about the CANDIDATE.
#
# Reproduced over HTTP before this file existed. Courier A has paid the shop
# and is carrying the food; his phone dies, so his fix goes stale — which is
# exactly the order an operator would press redispatch on:
#
#   redispatch → "Offered to Courier C."
#   C accepts  → 200, order courier now: Courier C
#
# The same corruption the reassign guard closed (see
# `no_reassignment_after_the_shop_is_paid_spec.rb`) — C told he paid, A
# stripped of a job he holds the food for — through a second door the guard
# did not cover. With A's fix fresh, it offered A the job HE ALREADY HAD.
#
# ── WHERE THE RULE LIVES ──────────────────────────────────────────────────
#
# In `OfferService`, so every caller gets it — the console, the merchant's
# accept, the expiry sweep, a decline's re-offer. Reassigning a job that has a
# courier is `#reassign`, which says who and records it; redispatch is not a
# second way to do that. And again at ACCEPT, inside the courier lock, for an
# offer that was live when the job was taken some other way.
RSpec.describe "a taken job is never offered", type: :request do
  let(:admin) { AdminUser.create!(name: "Ops", email: "ops@karwan.af", password: "a-long-test-password") }
  let(:merchant) { create(:merchant, latitude: 34.5553, longitude: 69.2075) }
  let(:holder) { create(:user, :courier, name: "Courier A") }
  let(:other) { create(:user, :courier, name: "Courier C") }

  before do
    [ holder, other ].each do |courier|
      courier.courier_profile.update!(is_available: true, last_latitude: 34.5553, last_longitude: 69.2075,
                                      location_updated_at: Time.current)
      courier.courier_wallet.update!(balance: 5_000, credit_line: 500)
    end
    post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
  end

  def carried_order
    create(:order, :with_items, :picked_up, merchant: merchant, courier: holder, merchant_paid_at: 5.minutes.ago,
                                            items_total: 400, customer_total: 500, commission: 50,
                                            courier_fee: 100, merchant_payout: 350)
  end

  it "offers nobody a job the courier is carrying, even with his phone dead" do
    order = carried_order
    holder.courier_profile.update!(location_updated_at: 20.minutes.ago)

    patch "/admin/orders/#{order.id}/redispatch"

    expect(order.offers.reload).to be_empty
    expect(order.reload.courier_id).to eq(holder.id)
  end

  it "does not offer the courier a job he already has" do
    order = carried_order

    patch "/admin/orders/#{order.id}/redispatch"

    expect(order.offers.reload).to be_empty
  end

  it "tells the operator the job is taken, and by whom it can be moved" do
    order = carried_order

    patch "/admin/orders/#{order.id}/redispatch"
    follow_redirect!

    expect(CGI.unescapeHTML(response.body)).to include("already with Courier A")
  end

  # An offer can outlive the moment its job was taken — e.g. an operator
  # reassigned by hand while it was live. Accepting it must not move the job.
  it "refuses an accept on a job that was taken after the offer went out" do
    order = create(:order, :with_items, :ready, merchant: merchant)
    offer = order.offers.create!(courier: other, sequence: 1, status: :offered,
                                 offered_at: Time.current, expires_at: 1.minute.from_now)
    order.update_columns(courier_id: holder.id)

    post "/api/v1/courier/offers/#{offer.id}/accept",
         headers: { "Authorization" => "Bearer #{UserSession.issue!(other).last}" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body)["code"]).to eq("job_taken")
    expect(order.reload.courier_id).to eq(holder.id)
  end

  # The console refuses before it reaches the service, so the request examples
  # above would stay green with the service's own rule deleted. The expiry
  # sweep, a decline's re-offer and the merchant's accept call the service
  # directly — this is the example that speaks for them.
  it "is refused by the offer service itself, whoever calls it" do
    order = carried_order

    expect(Dispatch::OfferService.new(order).call).to be_nil
    expect(Dispatch::OfferService.new(order).blocked_reason).to eq(:already_taken)
    expect(order.offers.reload).to be_empty
  end

  it "still dispatches an order nobody has taken" do
    order = create(:order, :with_items, :ready, merchant: merchant)

    patch "/admin/orders/#{order.id}/redispatch"

    expect(order.offers.reload.map(&:courier_id)).to be_present
  end
end
