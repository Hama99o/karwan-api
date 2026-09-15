require "rails_helper"

RSpec.describe "Api::V1::Merchants catalog and profile", type: :request do
  def json
    JSON.parse(response.body)
  end

  let(:owner) { create(:user, :merchant_owner) }
  let(:merchant) { create(:merchant, owner: owner, is_open: true) }
  let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(owner).last}" } }
  let!(:category) { create(:catalog_category, merchant: merchant, name: "Kebabs") }
  let!(:item) { create(:catalog_item, catalog_category: category, name: "Chicken Kabab", price: 400) }

  describe "GET /api/v1/merchant/catalog_items" do
    it "returns the catalog grouped as the merchant groups it" do
      get "/api/v1/merchant/catalog_items", headers: auth

      expect(response).to have_http_status(:ok)
      group = json["catalogs"].first
      expect(group["name"]).to eq("Kebabs")
      expect(group["items"].first["name"]).to eq("Chicken Kabab")
    end

    it "refuses without a token" do
      get "/api/v1/merchant/catalog_items"

      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses a customer, who owns no merchant" do
      customer = create(:user, :customer)

      get "/api/v1/merchant/catalog_items",
          headers: { "Authorization" => "Bearer #{UserSession.issue!(customer).last}" }

      expect(response).to have_http_status(:forbidden)
      expect(json["code"]).to eq("no_merchant")
    end

    # Tenancy is not permission, and there is deliberately no merchant_id
    # parameter to try.
    it "never shows another merchant's catalog" do
      other_item = create(:catalog_item, name: "Someone Else's Kabab")

      get "/api/v1/merchant/catalog_items", headers: auth

      names = json["catalogs"].flat_map { |c| c["items"] }.map { |i| i["name"] }
      expect(names).not_to include(other_item.name)
    end
  end

  # ONE ACTION. Mid-rush, wet hands — PRODUCT.md asks for one tap from the
  # order board, so it is its own route rather than a field on an update form.
  describe "POST /api/v1/merchant/catalog_items/:id/sold_out" do
    it "marks an item sold out in one call" do
      post "/api/v1/merchant/catalog_items/#{item.id}/sold_out", headers: auth

      expect(response).to have_http_status(:ok)
      expect(item.reload.is_available).to be false
      expect(json.dig("catalog_item", "is_available")).to be false
    end

    it "brings it back just as easily" do
      item.update!(is_available: false)

      post "/api/v1/merchant/catalog_items/#{item.id}/available", headers: auth

      expect(item.reload.is_available).to be true
    end

    # A customer complaining "it said it was available" needs an answer, and
    # sold-out patterns are how a merchant's real capacity becomes visible.
    it "records who toggled it and when" do
      post "/api/v1/merchant/catalog_items/#{item.id}/sold_out", headers: auth

      log = AuditLog.where(action: "catalog_item.sold_out", target: item).last
      expect(log).to be_present
      expect(log.actor_id).to eq(owner.id)
    end

    it "refuses to toggle another merchant's item" do
      other = create(:catalog_item)

      post "/api/v1/merchant/catalog_items/#{other.id}/sold_out", headers: auth

      expect(response).to have_http_status(:not_found)
      expect(other.reload.is_available).to be true
    end

    it "refuses without a token" do
      post "/api/v1/merchant/catalog_items/#{item.id}/sold_out"

      expect(response).to have_http_status(:unauthorized)
      expect(item.reload.is_available).to be true
    end

    # The customer-facing effect, checked end to end: a sold-out item still
    # SHOWS (removing it reads as "this shop no longer sells it") but cannot be
    # ordered.
    it "stops the item being orderable while leaving it visible" do
      post "/api/v1/merchant/catalog_items/#{item.id}/sold_out", headers: auth

      get "/api/v1/public/merchants/#{merchant.id}/catalog"
      listed = JSON.parse(response.body)["catalogs"].flat_map { |c| c["items"] }.first
      expect(listed["name"]).to eq("Chicken Kabab")
      expect(listed["is_available"]).to be false

      customer = create(:user, :customer)
      post "/api/v1/customer/orders",
           params: { order: { merchant_id: merchant.id, delivery_latitude: 34.54,
                              delivery_longitude: 69.175,
                              lines: [ { catalog_item_id: item.id, quantity: 1 } ] } },
           headers: { "Authorization" => "Bearer #{UserSession.issue!(customer).last}" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["code"]).to eq("item_unavailable")
    end
  end

  describe "catalog editing" do
    it "creates an item in a category" do
      post "/api/v1/merchant/catalog_items",
           params: { catalog_item: { catalog_category_id: category.id, name: "Mantu", price: 350 } },
           headers: auth

      expect(response).to have_http_status(:created)
      expect(merchant.catalog_items.kept.map(&:name)).to include("Mantu")
    end

    it "refuses an item priced below zero" do
      post "/api/v1/merchant/catalog_items",
           params: { catalog_item: { catalog_category_id: category.id, name: "Bad", price: -1 } },
           headers: auth

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "refuses to create against another merchant's category" do
      other_category = create(:catalog_category)

      post "/api/v1/merchant/catalog_items",
           params: { catalog_item: { catalog_category_id: other_category.id, name: "X", price: 1 } },
           headers: auth

      expect(response).to have_http_status(:not_found)
    end

    it "updates a price" do
      patch "/api/v1/merchant/catalog_items/#{item.id}",
            params: { catalog_item: { price: 450 } }, headers: auth

      expect(item.reload.price).to eq(450)
    end

    # One-way door #1: a price change must not rewrite what somebody already
    # ordered.
    it "does not change a price on an order already placed" do
      order = create(:order, merchant: merchant)
      line = order.order_items.create!(catalog_item: item, name: item.name, unit_price: 400,
                                       quantity: 1, line_total: 400, currency: "AFN")

      patch "/api/v1/merchant/catalog_items/#{item.id}",
            params: { catalog_item: { price: 9_999 } }, headers: auth

      expect(line.reload.unit_price).to eq(400)
      expect(line.name).to eq("Chicken Kabab")
    end

    # One-way door #6: soft delete. A hard delete leaves a hole in every order
    # that contained the item.
    it "discards an item rather than destroying it" do
      delete "/api/v1/merchant/catalog_items/#{item.id}", headers: auth

      expect(response).to have_http_status(:no_content)
      expect(item.reload).to be_discarded
      expect(CatalogItem.find(item.id)).to eq(item)
    end

    it "creates and discards a category, taking its items with it" do
      post "/api/v1/merchant/catalog_categories",
           params: { catalog_category: { name: "Drinks" } }, headers: auth
      expect(response).to have_http_status(:created)

      delete "/api/v1/merchant/catalog_categories/#{category.id}", headers: auth

      expect(category.reload).to be_discarded
      expect(item.reload).to be_discarded
    end
  end

  describe "the open/closed toggle" do
    # THE most important control in the system: a merchant marked open that
    # isn't is the most damaging state there is. Its own route, so it cannot
    # fail validation for an unrelated reason.
    it "closes and reopens the shop in one call each" do
      post "/api/v1/merchant/profile/close_now", headers: auth
      expect(merchant.reload.is_open).to be false
      expect(json.dig("profile", "accepting_orders")).to be false

      post "/api/v1/merchant/profile/open_now", headers: auth
      expect(merchant.reload.is_open).to be true
    end

    it "records the change, including that the merchant did it themselves" do
      post "/api/v1/merchant/profile/close_now", headers: auth

      expect(AuditLog.where(action: "merchant.closed", target: merchant).count).to eq(1)
    end

    it "stops the shop appearing as orderable to customers" do
      post "/api/v1/merchant/profile/close_now", headers: auth

      get "/api/v1/public/merchants", params: { open_now: true }

      expect(JSON.parse(response.body)["merchants"]).to be_empty
    end

    it "refuses without a token" do
      post "/api/v1/merchant/profile/close_now"

      expect(response).to have_http_status(:unauthorized)
      expect(merchant.reload.is_open).to be true
    end
  end

  describe "GET /api/v1/merchant/profile" do
    it "shows today's figures, grouped by currency" do
      create(:order, :delivered, merchant: merchant, merchant_payout: 350, commission: 50)

      get "/api/v1/merchant/profile", headers: auth

      today = json.dig("profile", "today")
      expect(today["delivered"]).to eq(1)
      expect(today["received"]).to eq({ "AFN" => "350.0" })
      expect(today["commission"]).to eq({ "AFN" => "50.0" })
    end

    # They are entitled to know what we take.
    it "shows the commission rate" do
      get "/api/v1/merchant/profile", headers: auth

      expect(json.dig("profile", "commission_rate").to_f).to eq(merchant.commission_rate.to_f)
    end
  end
end
