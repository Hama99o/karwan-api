require "rails_helper"

RSpec.describe "Api::V1::Public::Merchants", type: :request do
  def json
    JSON.parse(response.body)
  end

  let!(:open_merchant) do
    create(:merchant, :with_menu, name: "Shar-e-Naw Kabab House",
                                  latitude: 34.5553, longitude: 69.2075)
  end

  describe "GET /api/v1/public/merchants" do
    describe "browsing without a login" do
      # The load-bearing behaviour of correction 10. A user talked into
      # installing this must reach a merchant before being asked for anything.
      it "works with no token at all" do
        get "/api/v1/public/merchants"

        expect(response).to have_http_status(:ok)
        expect(json["merchants"].size).to eq(1)
      end

      it "returns pagination metadata the app can page with" do
        get "/api/v1/public/merchants"

        expect(json.dig("meta", "pagination")).to include(
          "current_page" => 1, "total_count" => 1, "total_pages" => 1
        )
      end

      it "honours a requested page size" do
        create_list(:merchant, 3)

        get "/api/v1/public/merchants", params: { page: { number: 1, size: 2 } }

        expect(json["merchants"].size).to eq(2)
        expect(json.dig("meta", "pagination", "total_pages")).to eq(2)
      end

      it "clamps an abusive page size rather than obeying it" do
        get "/api/v1/public/merchants", params: { page: { number: 1, size: 100_000 } }

        expect(response).to have_http_status(:ok)
        expect(json["merchants"].size).to be <= ApplicationController::MAX_PAGE_SIZE
      end
    end

    describe "what a customer may and may not see" do
      it "hides a merchant that is not yet approved" do
        create(:merchant, :pending, name: "Not Approved Yet")

        get "/api/v1/public/merchants"

        expect(json["merchants"].map { |m| m["name"] }).not_to include("Not Approved Yet")
      end

      it "hides a suspended merchant" do
        create(:merchant, :suspended, name: "Suspended Shop")

        get "/api/v1/public/merchants"

        expect(json["merchants"].map { |m| m["name"] }).not_to include("Suspended Shop")
      end

      it "hides a discarded merchant" do
        create(:merchant, name: "Gone").discard!

        get "/api/v1/public/merchants"

        expect(json["merchants"].map { |m| m["name"] }).not_to include("Gone")
      end

      # A closed merchant is SHOWN, greyed, with when it opens. Hiding it makes
      # the app look empty at 7am.
      it "shows a closed merchant, flagged as not accepting orders" do
        create(:merchant, :closed, name: "Closed For Now")

        get "/api/v1/public/merchants"

        closed = json["merchants"].find { |m| m["name"] == "Closed For Now" }
        expect(closed).to be_present
        expect(closed["accepting_orders"]).to be false
        expect(closed["is_open"]).to be false
      end

      it "can be asked for open merchants only" do
        create(:merchant, :closed, name: "Closed For Now")

        get "/api/v1/public/merchants", params: { open_now: true }

        expect(json["merchants"].map { |m| m["name"] }).to eq([ open_merchant.name ])
      end

      # Nothing operational belongs in a customer payload. A serializer that
      # carried it "for later" is how it leaks.
      it "never exposes the commission rate, the owner's identity or the licence" do
        get "/api/v1/public/merchants"

        keys = json["merchants"].first.keys
        expect(keys).not_to include("commission_rate", "owner_name", "owner_phone",
                                    "owner_national_id_number", "license_number",
                                    "verified_by_id", "rejection_reason")
      end
    end

    describe "search" do
      # People search for a DISH, not a shop. "mantu" is food.
      it "finds a merchant by a dish it sells" do
        other = create(:merchant, name: "Mantu Place")
        category = create(:catalog_category, merchant: other)
        create(:catalog_item, catalog_category: category, name: "Mantu")

        get "/api/v1/public/merchants", params: { q: "mantu" }

        expect(json["merchants"].map { |m| m["name"] }).to eq([ "Mantu Place" ])
      end

      it "finds a merchant by name" do
        get "/api/v1/public/merchants", params: { q: "kabab" }

        expect(json["merchants"].size).to eq(1)
      end

      it "returns an empty list rather than everything for no match" do
        get "/api/v1/public/merchants", params: { q: "sushi" }

        expect(json["merchants"]).to eq([])
      end
    end

    describe "distance and ETA" do
      it "is computed by the SERVER when the customer sends a position" do
        get "/api/v1/public/merchants", params: { latitude: 34.5400, longitude: 69.1750 }

        merchant = json["merchants"].first
        expect(merchant["distance_km"]).to be_within(1.0).of(4.3)
        expect(merchant["eta_minutes"]).to be_positive
      end

      it "includes the kitchen in the ETA, not just the travel" do
        get "/api/v1/public/merchants", params: { latitude: 34.5400, longitude: 69.1750 }

        merchant = json["merchants"].first
        travel = Geo::Distance.travel_minutes(merchant["distance_km"])
        expect(merchant["eta_minutes"]).to eq(travel + open_merchant.effective_prep_time_minutes)
      end

      it "is nil, not zero, when the customer sends no position" do
        get "/api/v1/public/merchants"

        expect(json["merchants"].first["distance_km"]).to be_nil
      end

      it "orders nearest first when a position is given" do
        create(:merchant, name: "Far Away", latitude: 34.7000, longitude: 69.5000)

        get "/api/v1/public/merchants", params: { latitude: 34.5553, longitude: 69.2075 }

        expect(json["merchants"].map { |m| m["name"] }.first).to eq(open_merchant.name)
      end

      it "orders alphabetically when no position is given, never randomly" do
        create(:merchant, name: "Aaa First")

        get "/api/v1/public/merchants"

        expect(json["merchants"].map { |m| m["name"] }.first).to eq("Aaa First")
      end
    end

    describe "localisation" do
      it "names the merchant kind in the requested locale" do
        get "/api/v1/public/merchants", params: { locale: "ps" }

        expect(json["merchants"].first["kind_name"]).to eq(open_merchant.merchant_kind.name_ps)
      end

      it "prefers the signed-in user's own locale over the parameter" do
        user = create(:user, locale: "ps")
        _, token = UserSession.issue!(user)

        get "/api/v1/public/merchants", params: { locale: "en" },
                                        headers: { "Authorization" => "Bearer #{token}" }

        expect(json["merchants"].first["kind_name"]).to eq(open_merchant.merchant_kind.name_ps)
      end
    end
  end

  describe "GET /api/v1/public/merchants/:id" do
    it "returns the detail a customer needs to decide" do
      get "/api/v1/public/merchants/#{open_merchant.id}"

      expect(response).to have_http_status(:ok)
      expect(json["merchant"]).to include("name", "phone", "landmark_note", "location", "opening_hours")
    end

    it "is 404 for a merchant that is not approved, not a 403 that reveals it exists" do
      hidden = create(:merchant, :pending)

      get "/api/v1/public/merchants/#{hidden.id}"

      expect(response).to have_http_status(:not_found)
    end

    it "is 404 for a discarded merchant" do
      open_merchant.discard!

      get "/api/v1/public/merchants/#{open_merchant.id}"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/public/merchants/:id/catalog" do
    it "returns the catalog grouped as the merchant groups it" do
      get "/api/v1/public/merchants/#{open_merchant.id}/catalog"

      expect(response).to have_http_status(:ok)
      category = json["catalogs"].first
      expect(category).to include("name", "items")
      expect(category["items"].first).to include("name", "price", "currency", "is_available")
    end

    # A customer looking for yesterday's kabab needs to see it is sold out
    # today. Removing it reads as "this shop no longer sells it".
    it "includes a sold-out item, flagged rather than hidden" do
      category = open_merchant.catalog_categories.first
      create(:catalog_item, :sold_out, catalog_category: category, name: "Sold Out Kabab")

      get "/api/v1/public/merchants/#{open_merchant.id}/catalog"

      item = json["catalogs"].flat_map { |c| c["items"] }.find { |i| i["name"] == "Sold Out Kabab" }
      expect(item).to be_present
      expect(item["is_available"]).to be false
    end

    it "excludes a discarded item entirely, because it is gone rather than unavailable" do
      category = open_merchant.catalog_categories.first
      create(:catalog_item, :discarded, catalog_category: category, name: "Deleted Item")

      get "/api/v1/public/merchants/#{open_merchant.id}/catalog"

      names = json["catalogs"].flat_map { |c| c["items"] }.map { |i| i["name"] }
      expect(names).not_to include("Deleted Item")
    end

    it "sends the option rules the client must enforce" do
      item = open_merchant.catalog_items.first
      size = create(:catalog_item_option, catalog_item: item, name: "Size",
                                          selection_type: :single, required: true)
      create(:catalog_item_option_value, catalog_item_option: size, name: "Large", price_delta: 100)

      get "/api/v1/public/merchants/#{open_merchant.id}/catalog"

      option = json["catalogs"].flat_map { |c| c["items"] }
                               .flat_map { |i| i["options"] }.compact.first
      expect(option).to include("name" => "Size", "minimum_required" => 1, "maximum_allowed" => 1)
      expect(option["values"].first).to include("name" => "Large")
    end

    it "hides an unavailable option value, which cannot be chosen anyway" do
      item = open_merchant.catalog_items.first
      size = create(:catalog_item_option, catalog_item: item, name: "Size")
      create(:catalog_item_option_value, catalog_item_option: size, name: "Gone", is_available: false)

      get "/api/v1/public/merchants/#{open_merchant.id}/catalog"

      values = json["catalogs"].flat_map { |c| c["items"] }.flat_map { |i| i["options"] }
                               .compact.flat_map { |o| o["values"] }
      expect(values.map { |v| v["name"] }).not_to include("Gone")
    end
  end

  describe "GET /api/v1/public/merchant_categories" do
    it "returns the seeded taxonomy in the requested locale" do
      create(:merchant_category, :kabab)

      get "/api/v1/public/merchant_categories", params: { locale: "fa" }

      expect(response).to have_http_status(:ok)
      kabab = json["merchant_categories"].find { |c| c["slug"] == "kabab" }
      expect(kabab["name"]).to eq("کباب")
    end

    it "excludes an inactive category" do
      create(:merchant_category, slug: "retired", is_active: false)

      get "/api/v1/public/merchant_categories"

      expect(json["merchant_categories"].map { |c| c["slug"] }).not_to include("retired")
    end
  end
end
