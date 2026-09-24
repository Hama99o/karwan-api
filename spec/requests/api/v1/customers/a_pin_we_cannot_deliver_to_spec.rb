require "rails_helper"

# ── A DELIVERY PIN OUTSIDE THE COUNTRY IS NOT PRICED, AND NOT PLACED ────────
#
# Found 2026-09-24. Nothing on the money path asked where the customer was:
#
#   (0, 0) — a device with no fix, or a map left on its default — quoted AND
#   PLACED at 8,117 km and a delivery fee of 162,396 AFN; the shop was alerted.
#   A pin in Paris placed at 111,693 AFN. "abc" quoted 200 at that fee and
#   then died unhandled on save.
#
# The drawn-route endpoint already refused every one of these with
# `Geo::Bounds`. Only the country is enforced here; how far from the shop a
# delivery may go is a separate question, and the owner's.
RSpec.describe "a pin we cannot deliver to", type: :request do
  def json
    JSON.parse(response.body)
  end

  let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(create(:user, :customer)).last}" } }
  let(:merchant) { create(:merchant, latitude: 34.5553, longitude: 69.2075) }
  let!(:kabab) { create(:catalog_item, catalog_category: create(:catalog_category, merchant: merchant), price: 400) }

  def cart(latitude, longitude)
    { order: { merchant_id: merchant.id, delivery_latitude: latitude, delivery_longitude: longitude,
               lines: [ { catalog_item_id: kabab.id, quantity: 1 } ] } }
  end

  {
    "null island — no fix at all" => %w[0 0],
    "Paris" => %w[48.8566 2.3522],
    "text" => %w[abc def],
    "nothing" => [ "", "" ],
    "off the planet" => %w[999 999]
  }.each do |what, (lat, lng)|
    describe what do
      it "is refused at the quote, in the words the map already uses" do
        post "/api/v1/customer/orders/quote", params: cart(lat, lng), headers: auth

        expect(response).to have_http_status(:unprocessable_content)
        expect(json["code"]).to eq("outside_service_area")
      end

      it "places nothing, and wakes no shop" do
        expect { post "/api/v1/customer/orders", params: cart(lat, lng), headers: auth }
          .not_to change(Order, :count)
        expect(json["code"]).to eq("outside_service_area")

        expect { post "/api/v1/customer/orders", params: cart(lat, lng), headers: auth }
          .not_to have_enqueued_job(Notifications::MerchantOrderAlertJob)
      end
    end
  end

  it "still prices and places a real Kabul pin" do
    post "/api/v1/customer/orders", params: cart("34.5400", "69.1750"), headers: auth

    expect(response).to have_http_status(:created)
  end
end
