require "rails_helper"

RSpec.describe "Api::V1::Merchants::Orders", type: :request do
  def json
    JSON.parse(response.body)
  end

  let(:owner) { create(:user, :merchant_owner) }
  let(:merchant) { create(:merchant, owner: owner) }
  let(:token) { UserSession.issue!(owner).last }
  let(:auth) { { "Authorization" => "Bearer #{token}" } }

  let!(:order) { create(:order, :with_items, merchant: merchant) }

  describe "GET /api/v1/merchant/orders" do
    describe "the happy path" do
      # The bug this caught before any spec ran: `policy_scope(Order)` resolves
      # to the CUSTOMER's own orders, so chaining a merchant filter onto it
      # returned an empty board. A scope per role, asked for explicitly.
      it "returns this merchant's live orders" do
        get "/api/v1/merchant/orders", headers: auth

        expect(response).to have_http_status(:ok)
        expect(json["orders"].map { |o| o["id"] }).to eq([ order.id ])
      end

      # A kitchen works the queue from the front. Newest-first would bury the
      # order that has waited longest — the opposite of the customer's list.
      it "puts the oldest order first" do
        newer = create(:order, merchant: merchant, created_at: 1.minute.ago)
        order.update_columns(created_at: 10.minutes.ago)

        get "/api/v1/merchant/orders", headers: auth

        expect(json["orders"].map { |o| o["id"] }).to eq([ order.id, newer.id ])
      end

      # Age in the CURRENT state, not since placement. An order accepted a
      # minute ago is not late; one unaccepted for ten minutes is.
      it "reports minutes in the current state, and whether that is overdue" do
        order.update_columns(placed_at: 30.minutes.ago, updated_at: 30.minutes.ago)

        get "/api/v1/merchant/orders", headers: auth

        card = json["orders"].first
        expect(card["minutes_in_state"]).to be >= 29
        expect(card["is_overdue"]).to be true
      end

      it "carries the items, their options and the customer's note" do
        item = order.order_items.first
        item.selected_options.create!(option_name: "Size", value_name: "Large", price_delta: 100)

        get "/api/v1/merchant/orders", headers: auth

        line = json["orders"].first["items"].first
        expect(line["name"]).to be_present
        expect(line["options"]).to include("Size: Large")
      end

      it "can be filtered to one status" do
        ready = create(:order, :ready, merchant: merchant)

        get "/api/v1/merchant/orders", params: { status: "ready" }, headers: auth

        expect(json["orders"].map { |o| o["id"] }).to eq([ ready.id ])
      end

      it "shows live orders only by default, so the board is the work queue" do
        create(:order, :delivered, merchant: merchant)

        get "/api/v1/merchant/orders", headers: auth

        expect(json["orders"].map { |o| o["id"] }).to eq([ order.id ])
      end
    end

    describe "the refused paths" do
      it "refuses without a token" do
        get "/api/v1/merchant/orders"

        expect(response).to have_http_status(:unauthorized)
      end

      # Tenancy is not permission. One restaurant must never read another's
      # orders, and there is deliberately no merchant_id parameter to try.
      it "never shows another merchant's orders" do
        other_order = create(:order)

        get "/api/v1/merchant/orders", headers: auth

        expect(json["orders"].map { |o| o["id"] }).not_to include(other_order.id)
      end

      it "refuses a customer, who holds no merchant" do
        customer = create(:user, :customer)
        customer_token = UserSession.issue!(customer).last

        get "/api/v1/merchant/orders", headers: { "Authorization" => "Bearer #{customer_token}" }

        expect(response).to have_http_status(:forbidden)
        expect(json["code"]).to eq("no_merchant")
      end

      it "refuses a merchant owner whose merchant was discarded" do
        merchant.discard!

        get "/api/v1/merchant/orders", headers: auth

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "GET /api/v1/merchant/orders/:id" do
    it "shows the commission and the payout, so the money is known before pickup" do
      get "/api/v1/merchant/orders/#{order.id}", headers: auth

      expect(json["order"]).to include("items_total", "commission", "merchant_payout")
    end

    # The merchant does not deliver, so they have no business holding a
    # customer's home location. That belongs to the courier's serializer.
    it "never exposes the customer's delivery address" do
      get "/api/v1/merchant/orders/#{order.id}", headers: auth

      expect(json["order"].keys).not_to include(
        "delivery_latitude", "delivery_longitude", "delivery_landmark_note", "delivery_location"
      )
    end

    it "is 404 for another merchant's order" do
      other = create(:order)

      get "/api/v1/merchant/orders/#{other.id}", headers: auth

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/merchant/orders/:id/accept" do
    it "accepts the order and records who did it" do
      post "/api/v1/merchant/orders/#{order.id}/accept", headers: auth

      expect(response).to have_http_status(:ok)
      expect(order.reload.status).to eq("accepted")
      expect(order.accepted_at).to be_present
      expect(order.transitions.last).to have_attributes(
        from_status: "placed", to_status: "accepted", actor_id: owner.id
      )
    end

    # Accepting is what makes an order dispatchable, so dispatch starts here
    # rather than on a timer — the courier's phone rings while the kitchen is
    # still putting the lid on.
    it "starts dispatch immediately" do
      courier = create(:user, :courier)
      courier.courier_profile.update!(is_available: true, last_latitude: merchant.latitude,
                                      last_longitude: merchant.longitude,
                                      location_updated_at: Time.current)
      courier.courier_wallet.update!(balance: 5_000, credit_line: 500)

      post "/api/v1/merchant/orders/#{order.id}/accept", headers: auth

      expect(order.reload.offers.pending.count).to eq(1)
      expect(order.offers.first.courier).to eq(courier)
    end

    it "still accepts when no courier is available, leaving it for admin" do
      post "/api/v1/merchant/orders/#{order.id}/accept", headers: auth

      expect(order.reload.status).to eq("accepted")
      expect(order.offers).to be_empty
    end

    it "refuses to accept an order that is already accepted" do
      order.update!(status: :accepted, accepted_at: Time.current)

      post "/api/v1/merchant/orders/#{order.id}/accept", headers: auth

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("invalid_transition")
    end

    it "refuses another merchant's order" do
      other = create(:order)

      post "/api/v1/merchant/orders/#{other.id}/accept", headers: auth

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/merchant/orders/:id/reject" do
    # A reason from a fixed list, because "failure reasons ranked" is a report
    # the owner asked for and free text cannot be counted.
    it "rejects with a reason from the list" do
      post "/api/v1/merchant/orders/#{order.id}/reject",
           params: { reason: "out_of_stock" }, headers: auth

      expect(response).to have_http_status(:ok)
      expect(order.reload.status).to eq("rejected")
      expect(order.rejection_reason).to eq("out_of_stock")
    end

    it "refuses a rejection with no reason" do
      post "/api/v1/merchant/orders/#{order.id}/reject", headers: auth

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("reason_required")
      expect(order.reload.status).to eq("placed")
    end

    it "refuses a reason that is not on the list" do
      post "/api/v1/merchant/orders/#{order.id}/reject",
           params: { reason: "did not feel like it" }, headers: auth

      expect(json["code"]).to eq("reason_required")
      expect(order.reload.status).to eq("placed")
    end
  end

  describe "POST /api/v1/merchant/orders/:id/ready" do
    it "marks a preparing order ready" do
      order.update!(status: :preparing, accepted_at: 5.minutes.ago, preparing_at: 2.minutes.ago)

      post "/api/v1/merchant/orders/#{order.id}/ready", headers: auth

      expect(response).to have_http_status(:ok)
      expect(order.reload.status).to eq("ready")
      expect(order.ready_at).to be_present
    end

    # The state machine is the authority on ordering. A machine cannot declare
    # food ready that nobody agreed to cook.
    it "refuses to mark a placed order ready, skipping the states between" do
      post "/api/v1/merchant/orders/#{order.id}/ready", headers: auth

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("invalid_transition")
      expect(order.reload.status).to eq("placed")
    end
  end
end
