require "rails_helper"

# ── HE PAYS NO MORE THAN HIS CONFIRM SCREEN SAID ────────────────────────────
#
# Measured 24 Sept 2026: quoted 518.56, the shop raised a price, the tap
# placed at 768.56 with a 201 and nothing said — and the courier at the door,
# reading the same frozen total, had no way to know anything needed
# explaining. With `expected_amount_to_pay_in_cash`, an increase is refused
# with the new quote; a decrease places at the lower figure.
RSpec.describe "paying what he was shown", type: :request do
  def json = JSON.parse(response.body)

  let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(create(:user, :customer)).last}" } }
  let(:merchant) { create(:merchant, latitude: 34.5553, longitude: 69.2075, commission_rate: 0.125) }
  let!(:item) { create(:catalog_item, catalog_category: create(:catalog_category, merchant: merchant), price: 400) }
  let(:cart) do
    { order: { merchant_id: merchant.id, delivery_latitude: "34.54", delivery_longitude: "69.175",
               lines: [ { catalog_item_id: item.id, quantity: 1 } ] } }
  end

  def shown
    post "/api/v1/customer/orders/quote", params: cart, headers: auth
    json.dig("quote", "amount_to_pay_in_cash").to_d
  end

  def place(expected, headers: auth)
    post "/api/v1/customer/orders", params: cart.merge(expected_amount_to_pay_in_cash: expected.to_s), headers: headers
  end

  it "refuses a price that has gone up, says what it is now, and places nothing" do
    was = shown
    item.update!(price: 650)

    expect { place(was) }.not_to change(Order, :count)
    expect(response).to have_http_status(:conflict)
    expect(json["code"]).to eq("price_changed")
    expect(json.dig("quote", "amount_to_pay_in_cash").to_d).to be > was
  end

  it "places a price that has gone down, at the lower figure, and keeps what he was shown" do
    was = shown
    item.update!(price: 300)

    place(was)

    expect(response).to have_http_status(:created)
    order = Order.last
    expect(order.customer_total).to be < was
    expect(order.shown_amount_to_pay_in_cash).to eq(was)
  end

  it "places an unchanged price as it always did" do
    place(shown)

    expect(response).to have_http_status(:created)
  end

  it "behaves as before for a build that sends no expected amount" do
    shown
    item.update!(price: 650)

    expect { post "/api/v1/customer/orders", params: cart, headers: auth }.to change(Order, :count).by(1)
  end

  it "refuses an expected amount that is not a number, as a client bug" do
    expect { place("abc") }.not_to change(Order, :count)
    expect(json["code"]).to eq("invalid_expected_amount")
  end

  # CHECKED TOGETHER with the Idempotency-Key (§E): a refusal placed nothing,
  # so the same key, sent again after he confirms the new price, places once.
  it "lets the retry under the same key place after he confirms the new price" do
    keyed = auth.merge("Idempotency-Key" => "5f0c7b1e-3a2d-4c8e-9b1f-7d6e5a4c3b2a")
    was = shown
    item.update!(price: 650)
    place(was, headers: keyed)
    expect(response).to have_http_status(:conflict)
    now = json.dig("quote", "amount_to_pay_in_cash")

    expect { place(now, headers: keyed) }.to change(Order, :count).by(1)
    expect(response).to have_http_status(:created)
    expect { place(now, headers: keyed) }.not_to change(Order, :count)
  end
end
