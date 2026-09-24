require "rails_helper"

# `item_unavailable` named the line only in an English `error`, so the cart
# could say "something here is unavailable" and leave the customer to find
# which of six things it was — or parse English to find out. It now carries
# `catalog_item_ids`, for EVERY unavailable line, not the first one met.
RSpec.describe "which line is sold out", type: :request do
  def json = JSON.parse(response.body)

  let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(create(:user, :customer)).last}" } }
  let(:merchant) { create(:merchant, latitude: 34.5553, longitude: 69.2075) }
  let(:category) { create(:catalog_category, merchant: merchant) }
  let!(:kabab) { create(:catalog_item, catalog_category: category, price: 400) }
  let!(:bolani) { create(:catalog_item, catalog_category: category, price: 150) }
  let!(:tea) { create(:catalog_item, catalog_category: category, price: 30) }

  def cart(*lines)
    { order: { merchant_id: merchant.id, delivery_latitude: "34.54", delivery_longitude: "69.175", lines: lines } }
  end

  %w[/api/v1/customer/orders/quote /api/v1/customer/orders].each do |path|
    describe "POST #{path}" do
      it "names every sold-out line by id, not only the first" do
        kabab.update!(is_available: false)
        tea.update!(is_available: false)

        post path, params: cart({ catalog_item_id: kabab.id, quantity: 1 }, { catalog_item_id: bolani.id, quantity: 1 },
                                { catalog_item_id: tea.id, quantity: 2 }), headers: auth

        expect(response).to have_http_status(:unprocessable_content)
        expect(json["code"]).to eq("item_unavailable")
        expect(json["catalog_item_ids"]).to contain_exactly(kabab.id, tea.id)
      end
    end
  end

  it "marks the line whose chosen OPTION is sold out" do
    size = create(:catalog_item_option, catalog_item: bolani)
    large = create(:catalog_item_option_value, catalog_item_option: size, is_available: false)

    post "/api/v1/customer/orders/quote",
         params: cart({ catalog_item_id: bolani.id, quantity: 1, option_value_ids: [ large.id ] }), headers: auth

    expect(json["catalog_item_ids"]).to eq([ bolani.id ])
  end

  it "names an item that is no longer on the menu at all" do
    gone = kabab.id
    kabab.discard!

    post "/api/v1/customer/orders/quote", params: cart({ catalog_item_id: gone, quantity: 1 }), headers: auth

    expect(json["catalog_item_ids"]).to eq([ gone ])
  end
end
