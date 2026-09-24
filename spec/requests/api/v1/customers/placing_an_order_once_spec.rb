require "rails_helper"

# ── "PLACE ORDER" SENT TWICE PLACES ONE ORDER ───────────────────────────────
#
# The phone blocks a double tap. What it cannot know is whether a request
# whose answer never came back had landed, and a retry placed a second order.
# The app now sends an `Idempotency-Key` made when checkout opened — contract
# in docs/API_VOCABULARY.md §E.
RSpec.describe "placing an order at most once", type: :request do
  def json
    JSON.parse(response.body)
  end

  let(:customer) { create(:user, :customer) }
  let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(customer).last}" } }
  let(:merchant) { create(:merchant, latitude: 34.5553, longitude: 69.2075, commission_rate: 0.125) }
  let(:category) { create(:catalog_category, merchant: merchant) }
  let!(:kabab) { create(:catalog_item, catalog_category: category, name: "Chicken Kabab", price: 400) }
  let!(:bolani) { create(:catalog_item, catalog_category: category, name: "Bolani", price: 150) }
  let(:key) { "5f0c7b1e-3a2d-4c8e-9b1f-7d6e5a4c3b2a" }

  def cart(**changes)
    {
      order: {
        merchant_id: merchant.id,
        delivery_latitude: "34.5400", delivery_longitude: "69.1750",
        delivery_landmark_note: "Blue gate near the park",
        lines: [ { catalog_item_id: kabab.id, quantity: 1 }, { catalog_item_id: bolani.id, quantity: 2 } ]
      }.merge(changes)
    }
  end

  def place(body = cart, key: self.key, headers: auth)
    post "/api/v1/customer/orders", params: body, headers: key ? headers.merge("Idempotency-Key" => key) : headers
  end

  it "places two orders when no key is sent, exactly as before" do
    expect { 2.times { place(key: nil) } }.to change(Order, :count).by(2)
  end

  describe "the same request sent again" do
    before { place }

    let!(:first) { json }

    it "places nothing more" do
      expect { place }.not_to change(Order, :count)
    end

    it "is answered exactly as the first was" do
      place

      expect(response).to have_http_status(:created)
      expect(json).to eq(first)
    end

    # A retry is the same request however it is spelled.
    it "is recognised with the basket in another order, a coordinate padded, and a blank note sent" do
      reordered = cart(
        delivery_latitude: "34.540000",
        notes: "",
        lines: [ { catalog_item_id: bolani.id, quantity: "2" }, { catalog_item_id: kabab.id, quantity: 1 } ]
      )

      expect { place(reordered) }.not_to change(Order, :count)
      expect(response).to have_http_status(:created)
    end

    it "is still answered after the shop has closed" do
      merchant.update!(is_open: false)

      place

      expect(response).to have_http_status(:created)
      expect(json.dig("order", "code")).to eq(first.dig("order", "code"))
    end
  end

  describe "the same key with a different basket" do
    before { place }

    let!(:placed_code) { json.dig("order", "code") }

    it "is refused, and names the order that exists" do
      expect { place(cart(lines: [ { catalog_item_id: kabab.id, quantity: 3 } ])) }.not_to change(Order, :count)

      expect(response).to have_http_status(:conflict)
      expect(json["code"]).to eq("idempotency_key_reused")
      expect(json.dig("order", "code")).to eq(placed_code)
    end

    it "is refused for a moved pin too" do
      place(cart(delivery_latitude: "34.5500"))

      expect(response).to have_http_status(:conflict)
    end

    it "places the changed basket under a new key — the deliberate second order" do
      expect { place(cart(lines: [ { catalog_item_id: kabab.id, quantity: 3 } ]), key: "#{key}-2") }
        .to change(Order, :count).by(1)
    end
  end

  # Keys are per customer. Another person who happens to send the same key is
  # placing their own order — and must never be handed somebody else's.
  it "never answers one customer with another's order" do
    place
    theirs = json.dig("order", "code")
    other_auth = { "Authorization" => "Bearer #{UserSession.issue!(create(:user, :customer)).last}" }

    expect { place(headers: other_auth) }.to change(Order, :count).by(1)
    expect(json.dig("order", "code")).not_to eq(theirs)
  end

  it "refuses a malformed key and places nothing" do
    expect { place(key: "no spaces!") }.not_to change(Order, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(json["code"]).to eq("invalid_idempotency_key")
  end
end
