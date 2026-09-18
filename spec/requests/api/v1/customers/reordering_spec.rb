require "rails_helper"

# ═══ "ORDER THIS AGAIN" ════════════════════════════════════════════════════
#
# PRODUCT.md's customer list: **"Order history — past orders, itemised,
# re-orderable."** Every piece existed and nothing walked the journey:
# `catalog_item_id` is carried on each past line, `Orders::CartResolver` refuses
# an unavailable item, and no spec placed an order FROM a past one.
#
# Found by the phase walk asking three questions of each PRODUCT.md item —
# built, reachable, asserted. This one was the first two and not the third.
#
# ── THE CASE THAT MAKES IT WORTH WALKING ─────────────────────────────────
#
# A menu changes. The dish somebody ate last month may be sold out today,
# delisted, or renamed — and the snapshot on their order deliberately does NOT
# follow the menu (one-way door 1), so the history reads correctly while the
# re-order must fail honestly. That gap between "what I ate" and "what I can
# order" is the whole feature.
RSpec.describe "Api::V1::Customers re-ordering", type: :request do
  def json
    JSON.parse(response.body)
  end

  let(:customer) { create(:user, :customer) }
  let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(customer).last}" } }
  let(:merchant) { create(:merchant, is_open: true, latitude: 34.5553, longitude: 69.2075) }
  let(:category) { create(:catalog_category, merchant: merchant) }
  let!(:kabab) { create(:catalog_item, catalog_category: category, merchant: merchant, name: "Chicken Kabab", price: 400) }

  # A delivered order, the way history holds it.
  let!(:past) do
    order = create(:order, :delivered, customer: customer, merchant: merchant)
    create(:order_item, order: order, catalog_item: kabab, name: kabab.name,
                        unit_price: 400, quantity: 2, options_total: 0, line_total: 800)
    order
  end

  def lines_from_history
    get "/api/v1/customer/orders/#{past.id}", headers: auth
    json.dig("order", "items").map { |item| { catalog_item_id: item["catalog_item_id"], quantity: item["quantity"] } }
  end

  def place(lines)
    post "/api/v1/customer/orders", params: {
      order: {
        merchant_id: merchant.id,
        delivery_latitude: 34.5290, delivery_longitude: 69.1610,
        delivery_landmark_note: "Blue gate, second floor",
        lines: lines
      }
    }, headers: auth
  end

  it "places a new order from a past one's own lines" do
    lines = lines_from_history
    expect(lines.first[:catalog_item_id]).to be_present,
                                             "the past line has no pointer — nothing to re-order from"

    expect { place(lines) }.to change(Order, :count).by(1)

    expect(response).to have_http_status(:created)
    fresh = Order.order(:id).last
    expect(fresh.order_items.first.catalog_item_id).to eq(kabab.id)
    expect(fresh.order_items.first.quantity).to eq(2)
  end

  # The price is TODAY's, not the one on the old order. A snapshot is what was
  # charged; a re-order is a new purchase at the current menu price.
  it "charges today's price, not the price that was paid last month" do
    kabab.update!(price: 450)

    place(lines_from_history)

    expect(Order.order(:id).last.order_items.first.unit_price).to eq(450)
  end

  # ── WHEN THE MENU HAS MOVED ON ───────────────────────────────────────────
  it "refuses a dish that is sold out today, and says which one" do
    kabab.update!(is_available: false)

    place(lines_from_history)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Chicken Kabab"),
                             "the refusal does not name the dish — a customer cannot tell what to remove"
  end

  # One-way door 1: the ORDER keeps its snapshot even when the dish is gone, so
  # the history still reads correctly. Only the re-order pointer goes nil.
  it "keeps the history readable after the dish is deleted, with no pointer to re-order" do
    kabab.discard!

    get "/api/v1/customer/orders/#{past.id}", headers: auth

    line = json.dig("order", "items").first
    expect(line["name"]).to eq("Chicken Kabab"), "the snapshot followed the menu — one-way door 1"
    expect(line["unit_price"].to_f).to eq(400)
    expect(line["catalog_item_id"]).to be_nil,
                                       "a deleted dish still offers a re-order pointer that cannot resolve"
  end

  it "refuses a re-order whose pointer no longer resolves, rather than 500ing" do
    kabab.discard!

    place([ { catalog_item_id: kabab.id, quantity: 1 } ])

    expect(response.status).to be_between(400, 499),
                               "a delisted item produced #{response.status} — the app cannot show that to anybody"
  end
end
