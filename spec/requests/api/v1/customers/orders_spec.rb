require "rails_helper"

RSpec.describe "Api::V1::Customers::Orders", type: :request do
  def json
    JSON.parse(response.body)
  end

  let(:customer) { create(:user, :customer) }
  let(:token) { UserSession.issue!(customer).last }
  let(:auth) { { "Authorization" => "Bearer #{token}" } }

  let(:merchant) { create(:merchant, latitude: 34.5553, longitude: 69.2075, commission_rate: 0.125) }
  let(:category) { create(:catalog_category, merchant: merchant) }
  let!(:kabab) { create(:catalog_item, catalog_category: category, name: "Chicken Kabab", price: 400) }

  let(:cart) do
    {
      order: {
        merchant_id: merchant.id,
        delivery_latitude: 34.5400, delivery_longitude: 69.1750,
        delivery_landmark_note: "Blue gate near the park",
        lines: [ { catalog_item_id: kabab.id, quantity: 1 } ]
      }
    }
  end

  describe "POST /api/v1/customer/orders/quote" do
    # Correction 4: money is shown before it is owed.
    it "prices the cart without creating anything" do
      expect { post "/api/v1/customer/orders/quote", params: cart, headers: auth }
        .not_to change(Order, :count)

      expect(response).to have_http_status(:ok)
      expect(json["quote"]).to include("items_total", "delivery_fee", "amount_to_pay_in_cash",
                                        "distance_km", "duration_minutes")
      expect(json.dig("quote", "items_total").to_f).to eq(400)
    end

    # The whole point: the quote and the charge must be the same number, or the
    # customer is asked for something different at the door than they agreed.
    it "quotes exactly what placing the order will charge" do
      post "/api/v1/customer/orders/quote", params: cart, headers: auth
      quoted = json.dig("quote", "amount_to_pay_in_cash").to_f

      post "/api/v1/customer/orders", params: cart, headers: auth
      charged = json.dig("order", "amount_to_pay_in_cash").to_f

      expect(charged).to eq(quoted)
    end

    it "refuses a closed merchant before the customer builds a cart" do
      merchant.update!(is_open: false)

      post "/api/v1/customer/orders/quote", params: cart, headers: auth

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("merchant_unavailable")
    end

    it "refuses without a token" do
      post "/api/v1/customer/orders/quote", params: cart

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/customer/orders" do
    describe "the happy path" do
      it "places the order and returns it itemised" do
        expect { post "/api/v1/customer/orders", params: cart, headers: auth }
          .to change(Order, :count).by(1)

        expect(response).to have_http_status(:created)
        expect(json.dig("order", "code")).to match(/\AK\d{10}\z/)
        expect(json.dig("order", "status")).to eq("placed")
        expect(json.dig("order", "items").first).to include("name" => "Chicken Kabab", "quantity" => 1)
      end

      # THE SERVER PRICES THE ORDER. Nothing in the payload carries an amount.
      it "ignores any price the client tries to send" do
        cart[:order][:lines][0][:unit_price] = 1
        cart[:order][:customer_total] = 1

        post "/api/v1/customer/orders", params: cart, headers: auth

        expect(Order.last.items_total).to eq(400)
        expect(Order.last.customer_total).to eq(400 + Order.last.delivery_fee)
      end

      # One-way door #1: the line is a snapshot. A merchant editing the catalog
      # tomorrow must not rewrite what somebody ordered today.
      it "snapshots the name and price, so a later edit cannot rewrite history" do
        post "/api/v1/customer/orders", params: cart, headers: auth
        order = Order.last

        kabab.update!(name: "Renamed Kabab", price: 9_999)

        expect(order.order_items.first.name).to eq("Chicken Kabab")
        expect(order.order_items.first.unit_price).to eq(400)
      end

      it "survives the catalog item being deleted entirely" do
        post "/api/v1/customer/orders", params: cart, headers: auth
        order = Order.last

        kabab.discard!

        expect(order.reload.order_items.first.name).to eq("Chicken Kabab")
      end

      it "copies the delivery address rather than referencing a saved pin" do
        post "/api/v1/customer/orders", params: cart, headers: auth

        expect(Order.last).to have_attributes(
          delivery_latitude: BigDecimal("34.54"),
          delivery_longitude: BigDecimal("69.175"),
          delivery_landmark_note: "Blue gate near the park"
        )
      end

      it "defaults the contact number to the account's, and allows an override" do
        post "/api/v1/customer/orders", params: cart, headers: auth
        expect(Order.last.customer_phone).to eq(customer.phone)

        cart[:order][:customer_phone] = "+93700000555"
        post "/api/v1/customer/orders", params: cart, headers: auth
        expect(Order.last.customer_phone).to eq("+93700000555")
      end

      it "writes the first row of the order's history" do
        post "/api/v1/customer/orders", params: cart, headers: auth

        transition = Order.last.transitions.first
        expect(transition).to have_attributes(from_status: nil, to_status: "placed",
                                              actor_id: customer.id, actor_role: "customer")
      end

      it "charges the options as well as the item" do
        size = create(:catalog_item_option, catalog_item: kabab, name: "Size",
                                            selection_type: :single, required: true)
        large = create(:catalog_item_option_value, catalog_item_option: size,
                                                   name: "Large", price_delta: 150)
        cart[:order][:lines][0][:option_value_ids] = [ large.id ]

        post "/api/v1/customer/orders", params: cart, headers: auth

        item = Order.last.order_items.first
        expect(item.options_total).to eq(150)
        expect(item.line_total).to eq(550)
        expect(item.selected_options.first).to have_attributes(option_name: "Size", value_name: "Large")
      end

      it "multiplies by quantity" do
        cart[:order][:lines][0][:quantity] = 3

        post "/api/v1/customer/orders", params: cart, headers: auth

        expect(Order.last.order_items.first.line_total).to eq(1_200)
        expect(Order.last.items_total).to eq(1_200)
      end
    end

    describe "the refused paths" do
      it "refuses without a token" do
        post "/api/v1/customer/orders", params: cart

        expect(response).to have_http_status(:unauthorized)
        expect(Order.count).to eq(0)
      end

      # A form-encoded empty array arrives as [""] — one blank string, not an
      # empty list — so the obvious implementation 500s here. A customer with
      # an empty cart deserves a message they can act on.
      it "refuses an empty cart with a code, not a 500" do
        cart[:order][:lines] = []

        post "/api/v1/customer/orders", params: cart, headers: auth

        expect(response).to have_http_status(:unprocessable_content)
        expect(json["code"]).to eq("empty_cart")
        expect(Order.count).to eq(0)
      end

      it "refuses a cart of junk rather than crashing on it" do
        post "/api/v1/customer/orders",
             params: { order: cart[:order].merge(lines: [ "nonsense" ]) }, headers: auth

        expect(response).to have_http_status(:unprocessable_content)
        expect(json["code"]).to eq("empty_cart")
      end

      it "refuses a missing lines key entirely" do
        cart[:order].delete(:lines)

        post "/api/v1/customer/orders", params: cart, headers: auth

        expect(response).to have_http_status(:unprocessable_content)
        expect(json["code"]).to eq("empty_cart")
      end

      it "refuses a closed merchant" do
        merchant.update!(is_open: false)

        post "/api/v1/customer/orders", params: cart, headers: auth

        expect(response).to have_http_status(:unprocessable_content)
        expect(json["code"]).to eq("merchant_unavailable")
      end

      it "refuses a merchant that is not approved" do
        merchant.update!(status: :pending)

        post "/api/v1/customer/orders", params: cart, headers: auth

        expect(response).to have_http_status(:not_found)
      end

      it "refuses a sold-out item" do
        kabab.update!(is_available: false)

        post "/api/v1/customer/orders", params: cart, headers: auth

        expect(response).to have_http_status(:unprocessable_content)
        expect(json["code"]).to eq("item_unavailable")
      end

      # Ordering across merchants in one order is nonsense — one order, one
      # pickup.
      it "refuses an item belonging to a different merchant" do
        other_item = create(:catalog_item, catalog_category: create(:catalog_category))
        cart[:order][:lines][0][:catalog_item_id] = other_item.id

        post "/api/v1/customer/orders", params: cart, headers: auth

        expect(response).to have_http_status(:unprocessable_content)
        expect(json["code"]).to eq("item_unavailable")
      end

      # The client enforces the option rules too, but a client is a suggestion.
      # A required size missing here is an order the kitchen cannot make.
      it "refuses a missing required option" do
        create(:catalog_item_option, catalog_item: kabab, name: "Size",
                                     selection_type: :single, required: true)

        post "/api/v1/customer/orders", params: cart, headers: auth

        expect(response).to have_http_status(:unprocessable_content)
        expect(json["code"]).to eq("invalid_options")
      end

      it "refuses more choices than the option allows" do
        extras = create(:catalog_item_option, :multiple, catalog_item: kabab,
                                                          name: "Extras", max_selections: 1)
        two = 2.times.map { |i| create(:catalog_item_option_value, catalog_item_option: extras, name: "E#{i}") }
        cart[:order][:lines][0][:option_value_ids] = two.map(&:id)

        post "/api/v1/customer/orders", params: cart, headers: auth

        expect(json["code"]).to eq("invalid_options")
      end

      it "refuses an option value belonging to another item" do
        stranger = create(:catalog_item_option_value)
        cart[:order][:lines][0][:option_value_ids] = [ stranger.id ]

        post "/api/v1/customer/orders", params: cart, headers: auth

        expect(json["code"]).to eq("invalid_options")
      end

      it "refuses a zero or negative quantity" do
        cart[:order][:lines][0][:quantity] = 0

        post "/api/v1/customer/orders", params: cart, headers: auth

        expect(json["code"]).to eq("invalid_options")
      end

      it "leaves nothing behind when a line is rejected" do
        cart[:order][:lines] << { catalog_item_id: kabab.id, quantity: 0 }

        post "/api/v1/customer/orders", params: cart, headers: auth

        expect(Order.count).to eq(0)
        expect(OrderItem.count).to eq(0)
      end
    end
  end

  describe "GET /api/v1/customer/orders" do
    it "returns only this customer's orders" do
      mine = create(:order, customer: customer, merchant: merchant)
      create(:order, merchant: merchant)

      get "/api/v1/customer/orders", headers: auth

      expect(json["orders"].map { |o| o["id"] }).to eq([ mine.id ])
    end

    it "refuses without a token" do
      get "/api/v1/customer/orders"

      expect(response).to have_http_status(:unauthorized)
    end

    it "never shows the customer our commission or the courier's fee" do
      create(:order, customer: customer, merchant: merchant)

      get "/api/v1/customer/orders", headers: auth

      keys = json["orders"].first.keys
      expect(keys).not_to include("commission", "merchant_payout", "courier_fee")
    end
  end

  describe "GET /api/v1/customer/orders/:id" do
    let!(:order) { create(:order, :with_items, customer: customer, merchant: merchant) }

    it "returns the timeline with a timestamp per step" do
      order.transitions.create!(from_status: "placed", to_status: "accepted",
                                actor: merchant.owner, actor_role: :merchant_owner,
                                created_at: Time.current)

      get "/api/v1/customer/orders/#{order.id}", headers: auth

      expect(json.dig("order", "timeline").map { |t| t["status"] }).to include("accepted")
      expect(json.dig("order", "timeline").first["at"]).to be_present
    end

    # 404, not 403 — another customer's order should not be confirmed to exist.
    it "is 404 for another customer's order" do
      other = create(:order, merchant: merchant)

      get "/api/v1/customer/orders/#{other.id}", headers: auth

      expect(response).to have_http_status(:not_found)
    end

    it "shows the courier's first name only once assigned" do
      order.update!(courier: create(:user, :courier, name: "Abdullah Rahimi"))

      get "/api/v1/customer/orders/#{order.id}", headers: auth

      expect(json.dig("order", "courier", "name")).to eq("Abdullah")
    end
  end

  describe "POST /api/v1/customer/orders/:id/cancel" do
    it "cancels an order the merchant has not started" do
      order = create(:order, customer: customer, merchant: merchant)

      post "/api/v1/customer/orders/#{order.id}/cancel", headers: auth

      expect(response).to have_http_status(:ok)
      expect(order.reload.status).to eq("cancelled")
      expect(order.cancelled_by_role).to eq("customer")
    end

    it "records who cancelled it, in the audit log" do
      order = create(:order, customer: customer, merchant: merchant)

      post "/api/v1/customer/orders/#{order.id}/cancel", headers: auth

      expect(AuditLog.where(action: "order.cancelled", actor: customer).count).to eq(1)
    end

    # Once the kitchen has started, somebody has spent money on it.
    it "refuses once the order is being prepared" do
      order = create(:order, :preparing, customer: customer, merchant: merchant)

      post "/api/v1/customer/orders/#{order.id}/cancel", headers: auth

      expect(response).to have_http_status(:forbidden)
      expect(order.reload.status).to eq("preparing")
    end

    it "refuses to cancel someone else's order" do
      other = create(:order, merchant: merchant)

      post "/api/v1/customer/orders/#{other.id}/cancel", headers: auth

      expect(response).to have_http_status(:not_found)
    end
  end
end
