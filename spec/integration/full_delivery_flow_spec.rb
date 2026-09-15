require "rails_helper"

# ONE ORDER, THREE PHONES, through the real HTTP endpoints.
#
# Every other spec tests a layer. This one tests the claim — that a customer can
# order food, a merchant can accept it, a courier can be dispatched, deliver it,
# take the cash, and that the money lands where Model A says it should.
#
# It exists because "the endpoints pass their specs" and "an order can actually
# be completed" are different statements, and only the second one is the
# product. multi_magic shipped a screen that blanked on first use with every
# request spec green.
RSpec.describe "A delivery, end to end", type: :request do
  def json
    JSON.parse(response.body)
  end

  def sign_in(phone, name: nil)
    post "/api/v1/auth/otp", params: { phone: phone }
    code = JSON.parse(response.body).fetch("development_code")
    post "/api/v1/auth/session", params: { phone: phone, code: code, name: name }
    { "Authorization" => "Bearer #{JSON.parse(response.body).fetch('token')}" }
  end

  let!(:merchant) do
    create(:merchant, name: "Shar-e-Naw Kabab House", latitude: 34.5553, longitude: 69.2075,
                      commission_rate: 0.125, prep_time_minutes: 20)
  end
  let!(:category) { create(:catalog_category, merchant: merchant) }
  let!(:kabab) { create(:catalog_item, catalog_category: category, name: "Chicken Kabab", price: 400) }

  it "carries one order from a customer's phone to cash in a courier's hand" do
    # ---- 1. The customer browses BEFORE logging in -------------------------
    # Correction 10: a first-time user must reach a merchant without being
    # asked for anything.
    get "/api/v1/public/merchants", params: { latitude: 34.5400, longitude: 69.1750 }
    expect(response).to have_http_status(:ok)
    listed = json["merchants"].first
    expect(listed["name"]).to eq("Shar-e-Naw Kabab House")
    expect(listed["eta_minutes"]).to be_positive

    get "/api/v1/public/merchants/#{merchant.id}/catalog"
    item_id = json["catalogs"].first["items"].first["id"]
    expect(item_id).to eq(kabab.id)

    # ---- 2. Only now do they sign in ---------------------------------------
    customer_auth = sign_in("+93700001001", name: "احمد کریمی")
    customer = User.find_by!(phone: "+93700001001")

    cart = {
      order: {
        merchant_id: merchant.id,
        delivery_latitude: 34.5400, delivery_longitude: 69.1750,
        delivery_landmark_note: "دروازه آبی نزدیک پارک شهر نو",
        lines: [ { catalog_item_id: item_id, quantity: 1 } ]
      }
    }

    # ---- 3. They see the price BEFORE committing ---------------------------
    post "/api/v1/customer/orders/quote", params: cart, headers: customer_auth
    quoted = json.dig("quote", "amount_to_pay_in_cash").to_f
    expect(quoted).to be_positive

    post "/api/v1/customer/orders", params: cart, headers: customer_auth
    expect(response).to have_http_status(:created)
    order = Order.find(json.dig("order", "id"))
    # The number they agreed to is the number they will be asked for.
    expect(order.customer_total.to_f).to eq(quoted)
    expect(order.status).to eq("placed")

    # ---- 4. The merchant, on a tablet on a counter ------------------------
    owner = create(:user, :merchant_owner)
    merchant.update!(owner: owner)
    merchant_auth = { "Authorization" => "Bearer #{UserSession.issue!(owner).last}" }

    get "/api/v1/merchant/orders", headers: merchant_auth
    expect(json["orders"].map { |o| o["id"] }).to eq([ order.id ])
    expect(json["orders"].first["items"].first["name"]).to eq("Chicken Kabab")

    # A courier has to exist and be fundable before accepting dispatches.
    courier = create(:user, :courier, name: "عبدالله رحیمی")
    courier.courier_profile.update!(is_available: true, accepted_job_kinds: %w[delivery],
                                    last_latitude: 34.5560, last_longitude: 69.2080,
                                    location_updated_at: Time.current)
    courier.courier_wallet.update!(balance: 2_000, credit_line: 500)
    courier_auth = { "Authorization" => "Bearer #{UserSession.issue!(courier).last}" }

    post "/api/v1/merchant/orders/#{order.id}/accept", headers: merchant_auth
    expect(response).to have_http_status(:ok)
    expect(order.reload.status).to eq("accepted")

    # ---- 5. Accepting dispatched it, one courier, with a deadline ---------
    get "/api/v1/courier/offer", headers: courier_auth
    offer_id = json.dig("offer", "id")
    expect(offer_id).to be_present
    expect(json.dig("offer", "job", "seconds_remaining")).to be_positive
    # The courier is told what they earn and what they must advance, before
    # accepting anything.
    expect(json.dig("offer", "job", "earnings").to_f).to eq(order.courier_fee.to_f)
    expect(json.dig("offer", "job", "advance_required").to_f).to eq(order.merchant_payout.to_f)

    post "/api/v1/courier/offers/#{offer_id}/accept", headers: courier_auth
    expect(response).to have_http_status(:ok)
    expect(order.reload.courier_id).to eq(courier.id)
    # Accepting assigns the courier and NOTHING else. The kitchen's status is
    # the merchant's to move — a courier taking the job does not mean anyone
    # started cooking.
    expect(order.status).to eq("accepted")

    # ---- 5b. The kitchen cooks, then says it is ready ---------------------
    post "/api/v1/merchant/orders/#{order.id}/accept", headers: merchant_auth
    expect(response).to have_http_status(:unprocessable_content) # already accepted

    order.transition_to!(:preparing, actor: owner, actor_role: :merchant_owner)
    post "/api/v1/merchant/orders/#{order.id}/ready", headers: merchant_auth
    expect(response).to have_http_status(:ok)
    expect(order.reload.status).to eq("ready")

    # ---- 6. One screen, four steps ----------------------------------------
    get "/api/v1/courier/job", headers: courier_auth
    steps = json.dig("job", "steps")
    expect(steps.map { |s| s["key"] })
      .to eq(%w[go_to_merchant pay_merchant go_to_customer collect_and_deliver])
    expect(steps.count { |s| s["current"] }).to eq(1)

    post "/api/v1/courier/jobs/delivery/#{order.id}/advance",
         params: { step_key: "pay_merchant" }, headers: courier_auth
    expect(response).to have_http_status(:ok)
    expect(order.reload.status).to eq("picked_up")
    expect(order.merchant_paid_at).to be_present

    # The customer can watch it move, with a timestamp per step.
    get "/api/v1/customer/orders/#{order.id}", headers: customer_auth
    expect(json.dig("order", "timeline").map { |t| t["status"] })
      .to include("placed", "accepted", "picked_up")
    expect(json.dig("order", "courier", "name")).to eq("عبدالله")

    post "/api/v1/courier/jobs/delivery/#{order.id}/advance",
         params: { step_key: "collect_and_deliver" }, headers: courier_auth
    expect(response).to have_http_status(:ok)

    # ---- 7. Model A, checked against the brief's own arithmetic -----------
    order.reload
    expect(order.status).to eq("delivered")
    expect(order.payment_status).to eq("collected")

    commission = order.commission
    expect(commission).to eq((order.items_total * merchant.commission_rate).round(2))
    # The merchant was handed the items less our commission, in cash, at pickup.
    expect(order.merchant_payout).to eq(order.items_total - commission)
    # The customer paid the items plus delivery.
    expect(order.customer_total).to eq(order.items_total + order.delivery_fee)
    # And from the courier's side it reconciles: what they collected, less what
    # they advanced, less their fee, is exactly our commission.
    expect(order.customer_total - order.merchant_payout - order.courier_fee).to eq(commission)

    # The commission is owed from the prepaid wallet — one ledger entry, written
    # at the moment it happened.
    entry = WalletEntry.find_by!(source: order, kind: :commission)
    expect(entry.amount).to eq(-commission)
    expect(courier.courier_wallet.reload.balance).to eq(2_000 - commission)
    expect(entry.balance_after).to eq(courier.courier_wallet.balance)

    # Our exposure is that commission and nothing more, and it is visible as
    # cash the courier owes us until they settle.
    expect(Couriers::CashPosition.new(courier).held).to eq(commission)

    # ---- 8. The history is complete and attributed ------------------------
    transitions = order.transitions.chronological
    expect(transitions.map(&:to_status))
      .to eq(%w[placed accepted preparing ready picked_up delivered])
    # Attribution end to end: the customer placed it, the merchant moved it
    # through the kitchen, the courier carried it.
    expect(transitions.map(&:actor_id)).to eq(
      [ customer.id, owner.id, owner.id, owner.id, courier.id, courier.id ]
    )
    # Every step has its own timestamp column, not just the current status.
    expect([ order.placed_at, order.accepted_at, order.picked_up_at, order.delivered_at ])
      .to all(be_present)
  end
end
