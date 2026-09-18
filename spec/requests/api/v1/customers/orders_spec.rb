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
        expect(json.dig("order", "code")).to match(/\AK\d{6}\z/)
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
      # by-design: `.first.keys` raises on an empty list, so this cannot pass vacuously.
      expect(keys).not_to include("commission", "merchant_payout", "courier_fee")
    end
  end

  describe "GET /api/v1/customer/orders/:id" do
    let!(:order) { create(:order, :with_items, customer: customer, merchant: merchant) }

    # ── WHAT "ORDER THIS AGAIN" NEEDS, AND WHY IT IS NOT THE SNAPSHOT ────────
    #
    # `order_items` is a SNAPSHOT — name, price and options as they were — and
    # that is one of this project's six one-way doors: a merchant renaming a
    # dish tomorrow must not rewrite what somebody ordered today.
    #
    # But a snapshot cannot be re-ordered. It has no identity, so the app could
    # only match by NAME against the live menu, which finds the wrong dish the
    # first time a merchant has "Kabab" and "Kabab (large)".
    #
    # So the serializer carries POINTERS alongside the snapshot — the catalog
    # item id, the option value ids, and the merchant id — and they are exactly
    # that: pointers, nullable, never the source of what was charged. These
    # examples exist because nothing asserted they survive, and a re-order
    # feature built on fields nobody tests is one refactor from silently
    # falling back to name matching.
    # ── THE NUMBER A CUSTOMER ACTUALLY RINGS ────────────────────────────────
    #
    # The call that gets made: an item is wrong, the order is late, the courier
    # cannot find the gate. The payload carried `merchant_id` and
    # `merchant_name` and nothing to dial, so the app's contact sheet had a
    # merchant row with no number — and fetching the merchant separately to fill
    # one row is what correction 17 forbids.
    describe "ringing the shop" do
      it "carries the shop's phone while the order is live" do
        get "/api/v1/customer/orders/#{order.id}", headers: auth

        expect(json.dig("order", "merchant_phone")).to eq(merchant.phone)
      end

      # `phone` is the shop; `contact_person_phone` is a named human, and that
      # one belongs on the merchant profile, which is an operator surface. A
      # customer ringing about a kebab wants whoever picks up.
      it "is the shop's number and not the named contact's" do
        merchant.update!(phone: "+93780000111", contact_person_phone: "+93790000222")

        get "/api/v1/customer/orders/#{order.id}", headers: auth

        expect(json.dig("order", "merchant_phone")).to eq("+93780000111")
        expect(response.body).not_to include("+93790000222"),
                                     "the named contact's private number reached a customer"
      end

      # A number on a delivered order from three weeks ago is a customer ringing
      # a restaurant about something nobody there remembers.
      it "is withheld once the order is over" do
        order.update!(status: :delivered, delivered_at: Time.current)

        get "/api/v1/customer/orders/#{order.id}", headers: auth

        expect(json.dig("order", "is_live")).to be(false), "not terminal — the assertion below proves nothing"
        expect(json.dig("order", "merchant_phone")).to be_nil
      end

      # The list is the order history; the contact sheet is on the order page.
      # If this ever appears in the list, the list has started shipping a detail
      # payload twenty times over.
      it "is not in the order list" do
        get "/api/v1/customer/orders", headers: auth

        expect(json["orders"].first).not_to have_key("merchant_phone")
      end
    end

    describe "the pointers re-ordering needs" do
      it "carries the merchant id, so the app can open the right catalog" do
        get "/api/v1/customer/orders/#{order.id}", headers: auth

        expect(json.dig("order", "merchant_id")).to eq(merchant.id)
      end

      it "carries the catalog item id on every line" do
        get "/api/v1/customer/orders/#{order.id}", headers: auth

        ids = json.dig("order", "items").map { |item| item["catalog_item_id"] }
        # `all` is vacuously true on an empty list — an order serialised with no
        # items would pass "every line carries an id" while carrying no lines.
        expect(ids).not_to be_empty, "no items — the assertion below would be vacuous"
        expect(ids).to all(be_present)
      end

      # THE SNAPSHOT STILL WINS on anything the customer was charged for. If
      # these ever came from the live catalog, last month's receipt would change
      # when a price did.
      it "keeps the snapshot authoritative even though the pointer is present" do
        line = order.order_items.first
        item = line.catalog_item
        item.update!(name: "Renamed Since", price: line.unit_price + 500)

        get "/api/v1/customer/orders/#{order.id}", headers: auth

        shown = json.dig("order", "items").first
        expect(shown["name"]).to eq(line.name)
        expect(shown["unit_price"].to_f).to eq(line.unit_price.to_f)
        # And the pointer still points, so it can still be re-ordered — at the
        # NEW price, which is the customer's to accept in the cart.
        expect(shown["catalog_item_id"]).to eq(item.id)
      end

      # A DELISTED DISH LEAVES THE RECEIPT INTACT. `catalog_item_id` is
      # nullable for exactly this, and the app has to render the line and
      # refuse to re-order it rather than crash on a missing id.
      it "still renders a line whose dish has been deleted" do
        order.order_items.destroy_all
        line = create(:order_item, :delisted, order: order)

        get "/api/v1/customer/orders/#{order.id}", headers: auth

        shown = json.dig("order", "items").first
        expect(shown["name"]).to eq(line.name)
        expect(shown["catalog_item_id"]).to be_nil
      end
    end

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
  describe "GET /api/v1/customer/orders/:id/track" do
    let!(:order) { create(:order, :picked_up, customer: customer, merchant: merchant) }
    let(:courier_profile) { order.courier.courier_profile }

    describe "the happy path" do
      it "gives the map its three points" do
        courier_profile.record_location!(latitude: 34.5480, longitude: 69.1900)

        get "/api/v1/customer/orders/#{order.id}/track", headers: auth

        expect(response).to have_http_status(:ok)
        track = json["track"]
        expect(track.dig("pickup", "latitude").to_f).to eq(merchant.latitude.to_f)
        expect(track.dig("dropoff", "latitude").to_f).to eq(order.delivery_latitude.to_f)
        expect(track.dig("courier", "location", "latitude").to_f).to eq(34.548)
        expect(track.dig("courier", "location_fresh")).to be true
      end

      # AFGHAN_UX.md §6: the customer — "especially a woman expecting a stranger
      # at the door" — should be able to reach him before he arrives.
      it "carries the courier's first name and phone" do
        get "/api/v1/customer/orders/#{order.id}/track", headers: auth

        expect(json.dig("track", "courier", "phone")).to eq(order.courier.phone)
        # by-design: the line above asserts the courier phone, so the payload is populated.
        expect(json.dig("track", "courier", "name")).not_to include(" ")
      end

      # A pin that has not moved in twenty minutes reads as "he is standing
      # still", which is a worse lie than "we do not know where he is". Same
      # five minutes dispatch itself refuses a fix past.
      it "WITHHOLDS a stale position rather than drawing it" do
        courier_profile.update!(last_latitude: 34.5480, last_longitude: 69.1900,
                                location_updated_at: (CourierProfile::STALE_AFTER + 1.minute).ago)

        get "/api/v1/customer/orders/#{order.id}/track", headers: auth

        expect(json.dig("track", "courier", "location")).to be_nil
        expect(json.dig("track", "courier", "location_fresh")).to be false
        # The age is still sent, so the app can say how old the last sighting is.
        expect(json.dig("track", "courier", "located_at")).to be_present
      end

      it "withholds a fresh timestamp that carries no coordinates" do
        courier_profile.update!(last_latitude: nil, last_longitude: nil,
                                location_updated_at: Time.current)

        get "/api/v1/customer/orders/#{order.id}/track", headers: auth

        expect(json.dig("track", "courier", "location")).to be_nil
        expect(json.dig("track", "courier", "location_fresh")).to be false
      end

      # Before dispatch finds anyone, the map still has two of its three
      # points — which is the whole screen, minus the moving dot.
      it "has no courier before one is assigned" do
        waiting = create(:order, customer: customer, merchant: merchant)

        get "/api/v1/customer/orders/#{waiting.id}/track", headers: auth

        expect(response).to have_http_status(:ok)
        expect(json.dig("track", "courier")).to be_nil
        expect(json.dig("track", "pickup")).to be_present
      end
    end

    describe "the refused paths" do
      # THE reason this is an endpoint and not fields on the order serializer.
      # Without the liveness check a customer could watch a courier for the
      # rest of their shift from an order delivered last week.
      it "refuses a terminal order" do
        order.update!(status: :delivered, delivered_at: Time.current)

        get "/api/v1/customer/orders/#{order.id}/track", headers: auth

        expect(response).to have_http_status(:forbidden)
      end

      it "is 404 for somebody else's order" do
        other = create(:order, :picked_up)

        get "/api/v1/customer/orders/#{other.id}/track", headers: auth

        expect(response).to have_http_status(:not_found)
      end

      it "refuses without a token" do
        get "/api/v1/customer/orders/#{order.id}/track"

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
  describe "the quote ITEMISES, so the app never sums anything" do
    # `CartResolver` computed every per-line figure and `QuoteService`
    # discarded them, so the app had nothing server-computed per line and was
    # summing catalog prices on the device. CLAUDE.md forbids a client-computed
    # total and edu-safi shipped that failure three times.
    it "returns a priced line per cart line, with the options named" do
      large = kabab.options.create!(name: "Size", selection_type: :single, required: true,
                                    min_selections: 1, max_selections: 1)
      big = large.values.create!(name: "Large", price_delta: 100, currency: "AFN")

      post "/api/v1/customer/orders/quote", params: {
        order: cart[:order].merge(
          lines: [ { catalog_item_id: kabab.id, quantity: 2, option_value_ids: [ big.id ], notes: "no salt" } ]
        )
      }, headers: auth

      expect(response).to have_http_status(:ok)
      line = json.dig("quote", "lines").first
      expect(line["name"]).to eq("Chicken Kabab")
      expect(line["quantity"]).to eq(2)
      expect(line["unit_price"].to_f).to eq(400)
      expect(line["options_total"].to_f).to eq(100)
      # (400 + 100) × 2. The whole line multiplied, options included — not the
      # base price alone, which would show 900 and charge 1000.
      expect(line["line_total"].to_f).to eq(1000)
      expect(line["notes"]).to eq("no salt")
      expect(line.dig("options", 0, "name")).to eq("Large")
      expect(line.dig("options", 0, "price_delta").to_f).to eq(100)
    end

    it "keeps the line totals consistent with the items total it charges" do
      post "/api/v1/customer/orders/quote", params: {
        order: cart[:order].merge(
          lines: [ { catalog_item_id: kabab.id, quantity: 3 } ]
        )
      }, headers: auth

      lines_sum = json.dig("quote", "lines").sum { |line| line["line_total"].to_f }
      expect(lines_sum).to eq(json.dig("quote", "items_total").to_f)
    end

    # WHAT TO BRING. This field returned the total unchanged, which made it
    # useless, so the app computed its own advice — a money rule on the device.
    describe "suggested_notes" do
      # The fee is DISTANCE-based, so neither of these can be left to the
      # default settings — a first version assumed 400 + 100 and got 518.56,
      # which is the pricing working correctly and the test assuming.
      def fix_delivery_fee(amount)
        { "delivery_base_fee" => amount, "delivery_fee_per_km" => "0.0",
          "delivery_minimum_fee" => "0.0" }.each do |key, value|
          Setting.find_or_initialize_by(key: key).update!(value: value, value_type: :decimal)
        end
      end

      it "advises the next 500 when the total is awkward" do
        fix_delivery_fee("55.0")

        post "/api/v1/customer/orders/quote", params: cart, headers: auth

        # 400 + 55 = 455, so bring 500 — the note people carry.
        expect(json.dig("quote", "amount_to_pay_in_cash").to_f).to eq(455)
        expect(json.dig("quote", "suggested_notes").to_f).to eq(500)
      end

      it "advises 1,500 rather than 500 on a bigger total" do
        # The bug a flat "have change for 500" had: it is wrong advice above
        # 500, and the customer arrives with the wrong note.
        fix_delivery_fee("50.0")

        post "/api/v1/customer/orders/quote", params: {
          order: cart[:order].merge(lines: [ { catalog_item_id: kabab.id, quantity: 3 } ])
        }, headers: auth

        expect(json.dig("quote", "amount_to_pay_in_cash").to_f).to eq(1250)
        expect(json.dig("quote", "suggested_notes").to_f).to eq(1500)
      end

      it "says nothing when the total is a round hundred — a float covers it" do
        fix_delivery_fee("100.0")

        post "/api/v1/customer/orders/quote", params: cart, headers: auth

        expect(json.dig("quote", "amount_to_pay_in_cash").to_f).to eq(500)
        expect(json.dig("quote", "suggested_notes")).to be_nil
      end
    end
  end

  # The cart and the status screen must not advise differently about one order.
  it "puts the same change advice on a placed order" do
    post "/api/v1/customer/orders", params: cart, headers: auth
    order = Order.find(json.dig("order", "id"))

    get "/api/v1/customer/orders/#{order.id}", headers: auth

    expect(json["order"]).to have_key("suggested_notes")
  end
  # ── THE ARRIVAL RANGE, ON THE WIRE ──────────────────────────────────────────
  #
  # The key-set spec pins the KEY, using a delivered order where the value is
  # correctly null. These pin the VALUE, on an order that is actually live —
  # which is the only state the tracking screen ever shows one in.
  describe "the arrival window" do
    let!(:live) do
      create(:order, :picked_up, customer: customer, merchant: merchant, distance_km: 6.0)
    end

    it "is a range on a live order, on the order payload and the track payload alike" do
      get "/api/v1/customer/orders/#{live.id}", headers: auth
      detail = json.dig("order", "arrival_window")

      get "/api/v1/customer/orders/#{live.id}/track", headers: auth
      track = json.dig("track", "arrival_window")

      [ detail, track ].each do |window|
        expect(window).to be_present
        expect(Time.zone.parse(window["from"])).to be < Time.zone.parse(window["to"])
        expect(window["basis"]).to be_in(%w[measured assumed])
      end
    end

    it "is null once the order is terminal, because there is no arrival left to estimate" do
      live.update!(status: :delivered, delivered_at: Time.current)

      get "/api/v1/customer/orders/#{live.id}", headers: auth

      expect(json["order"]).to have_key("arrival_window")
      expect(json.dig("order", "arrival_window")).to be_nil
    end

    it "says `measured` once the courier is reporting, and `assumed` before that" do
      get "/api/v1/customer/orders/#{live.id}", headers: auth
      expect(json.dig("order", "arrival_window", "basis")).to eq("assumed")

      live.courier.courier_profile.record_location!(latitude: 34.5480, longitude: 69.1900)

      get "/api/v1/customer/orders/#{live.id}", headers: auth
      expect(json.dig("order", "arrival_window", "basis")).to eq("measured")
    end
  end
end
