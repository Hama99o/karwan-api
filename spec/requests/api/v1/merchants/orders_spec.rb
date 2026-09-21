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

      # The card's one big figure. Without it the board showed a code, an age
      # and an item count — and a merchant cannot tell a 180 AFN order from a
      # 920 AFN one, which is the first thing they want to know.
      it "carries the money on the CARD, not only on the detail screen" do
        get "/api/v1/merchant/orders", headers: auth

        card = json["orders"].first
        expect(card).to include("items_total", "merchant_payout")
        expect(card["merchant_payout"].to_f).to eq(order.merchant_payout.to_f)
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

        ids = json["orders"].map { |o| o["id"] }
        # His own order must be there, or the exclusion is true of an empty
        # board — which is what a broken scope returns. edu-safi's lesson is
        # that tenancy is not permission; a tenancy check that passes on
        # nothing proves neither.
        expect(ids).to include(order.id), "his own board is empty — the check below is vacuous"
        expect(ids).not_to include(other_order.id)
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

  # ── THE SHOP'S OWN BOARD MUST SEPARATE THE TWO ───────────────────────────
  #
  # The board showed `status: "rejected"` on its own history and a shop could
  # not tell an order it refused from one it never answered. **This is the
  # surface where that distinction is actionable** — the customer can only shop
  # elsewhere; the person holding this tablet is the one who can go and look at
  # it. PRODUCT.md's alert is "loud and repeating until acknowledged" precisely
  # because a push arrives on a counter in a noisy kitchen and nobody looks.
  describe "why an order ended, on the board" do
    def rejected(reason, actor:, actor_role: :merchant_owner)
      job = create(:order, :with_items, merchant: merchant)
      job.transition_to!(:rejected, actor: actor, actor_role: actor_role)
      job.update!(rejection_reason: reason)
      job
    end

    it "tells the shop which of its own refusals this was" do
      job = rejected(:too_busy, actor: owner)

      get "/api/v1/merchant/orders/#{job.id}", headers: auth

      expect(json["order"]["ended_reason"]).to eq(
        "outcome" => "rejected", "code" => "too_busy", "ended_by" => "merchant_owner"
      )
    end

    # THE ONE THE SHOP CAN ACT ON. Four of these in a week is a tablet nobody
    # is watching, and until now nothing on this board said so.
    it "tells the shop when nobody in it ever answered" do
      job = rejected(:no_answer, actor: nil, actor_role: :admin)

      get "/api/v1/merchant/orders/#{job.id}", headers: auth

      expect(json["order"]["ended_reason"]["code"]).to eq("no_answer")
      expect(json["order"]["ended_reason"]["ended_by"]).to eq("system")
    end

    it "says nothing about an order still on the board" do
      get "/api/v1/merchant/orders/#{order.id}", headers: auth

      expect(json["order"]["ended_reason"]).to be_nil
    end

    it "is on the list too, where the shop actually looks" do
      rejected(:no_answer, actor: nil, actor_role: :admin)

      get "/api/v1/merchant/orders", params: { status: "rejected" }, headers: auth

      expect(json["orders"].first["ended_reason"]["code"]).to eq("no_answer")
    end

    # The board is polled while a kitchen is busy. One extra query per card is
    # the shape that makes a screen slow without anyone noticing why.
    it "does not cost a query per card" do
      3.times { rejected(:no_answer, actor: nil, actor_role: :admin) }

      seen = []
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        seen << payload[:sql] unless payload[:name].to_s.in?([ "SCHEMA", "TRANSACTION" ])
      end
      get "/api/v1/merchant/orders", params: { status: "rejected" }, headers: auth
      ActiveSupport::Notifications.unsubscribe(subscriber)

      transition_queries = seen.count { |sql| sql.include?("status_transitions") }
      expect(transition_queries).to be <= 1,
                                    "#{transition_queries} queries for transitions — the preload is not being used"
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

    # ── THE COLUMN HOLDS IT; THE BOARD MAY NOT SEND IT ────────────────────
    #
    # `no_answer` is a real value of `rejection_reason` — the timeout job writes
    # it about a shop that never replied. Validating against the ENUM rather
    # than against `MERCHANT_REJECTION_REASONS` would let a shop that refused an
    # order file it as one nobody showed them, which is the one line on the
    # reports page that decides whether the owner rings a restaurant or
    # replaces a tablet.
    it "refuses the one reason only the system may write" do
      expect(Order.rejection_reasons).to have_key("no_answer"), "plant a storable value, or this proves nothing"

      post "/api/v1/merchant/orders/#{order.id}/reject",
           params: { reason: "no_answer" }, headers: auth

      expect(json["code"]).to eq("reason_required")
      expect(order.reload.status).to eq("placed")
      expect(order.rejection_reason).to be_nil
    end
  end

  describe "POST /api/v1/merchant/orders/:id/preparing" do
    # THE GAP THIS CLOSED, found by wiring the mobile board to the real API:
    # Order::TRANSITIONS goes accepted → preparing → ready, and there was no
    # route to `preparing`. So an accepted order had no button that worked —
    # Ready answered 422 `invalid_transition` and the board dead-ended.
    it "moves an accepted order to preparing, with an actor and a timestamp" do
      order.update!(status: :accepted, accepted_at: 2.minutes.ago)

      post "/api/v1/merchant/orders/#{order.id}/preparing", headers: auth

      expect(response).to have_http_status(:ok)
      expect(order.reload.status).to eq("preparing")
      expect(order.preparing_at).to be_present
      expect(order.transitions.last).to have_attributes(
        from_status: "accepted", to_status: "preparing", actor_id: owner.id
      )
    end

    # The whole reason this is a separate call rather than `ready` advancing
    # two states: two transitions written in one request would carry the same
    # timestamp, and "how long do orders sit in preparing" is the metric that
    # runs a delivery business. It cannot be backfilled.
    it "leaves preparing and ready as two separately timed transitions" do
      order.update!(status: :accepted, accepted_at: 2.minutes.ago)

      post "/api/v1/merchant/orders/#{order.id}/preparing", headers: auth
      order.reload.update_columns(preparing_at: 4.minutes.ago)
      post "/api/v1/merchant/orders/#{order.id}/ready", headers: auth

      expect(order.reload.status).to eq("ready")
      expect(order.ready_at - order.preparing_at).to be >= 200
    end

    it "refuses to start preparing an order nobody accepted" do
      post "/api/v1/merchant/orders/#{order.id}/preparing", headers: auth

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("invalid_transition")
      expect(order.reload.status).to eq("placed")
    end

    it "refuses another merchant's order" do
      other = create(:order, :accepted)

      post "/api/v1/merchant/orders/#{other.id}/preparing", headers: auth

      expect(response).to have_http_status(:not_found)
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
