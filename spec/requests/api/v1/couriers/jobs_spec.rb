require "rails_helper"

RSpec.describe "Api::V1::Couriers::Jobs", type: :request do
  def json
    JSON.parse(response.body)
  end

  let(:courier) { create(:user, :courier) }
  let(:token) { UserSession.issue!(courier).last }
  let(:auth) { { "Authorization" => "Bearer #{token}" } }
  let(:merchant) { create(:merchant, latitude: 34.5553, longitude: 69.2075) }

  before do
    courier.courier_profile.update!(is_available: true, accepted_job_kinds: %w[delivery ride],
                                    last_latitude: 34.5553, last_longitude: 69.2075,
                                    location_updated_at: Time.current)
    courier.courier_wallet.update!(balance: 5_000, credit_line: 500)
  end

  def delivery(status: :ready)
    order = create(:order, :with_items, status, merchant: merchant, courier: courier,
                                                items_total: 400, delivery_fee: 100,
                                                customer_total: 500, commission: 50,
                                                courier_fee: 100, merchant_payout: 350)
    %w[accepted preparing ready].each do |reached|
      order.transitions.create!(to_status: reached, actor_role: :merchant_owner, created_at: Time.current)
      break if reached == status.to_s
    end
    order
  end

  describe "GET /api/v1/courier/job" do
    it "returns nothing when they have no job" do
      get "/api/v1/courier/job", headers: auth

      expect(response).to have_http_status(:ok)
      expect(json["job"]).to be_nil
    end

    describe "a delivery, as a four-step list" do
      let!(:order) { delivery }

      it "serialises four steps in order" do
        get "/api/v1/courier/job", headers: auth

        steps = json.dig("job", "steps")
        expect(steps.map { |s| s["key"] }).to eq(
          %w[go_to_merchant pay_merchant go_to_customer collect_and_deliver]
        )
      end

      # The server decides what happens next, so the phone cannot disagree.
      it "marks exactly one step current" do
        get "/api/v1/courier/job", headers: auth

        steps = json.dig("job", "steps")
        expect(steps.count { |s| s["current"] }).to eq(1)
        expect(steps.find { |s| s["current"] }["key"]).to eq("go_to_merchant")
      end

      # Money before it is owed, at every step (correction 4).
      it "shows the advance before the pay step and the collection before the last" do
        get "/api/v1/courier/job", headers: auth

        steps = json.dig("job", "steps").index_by { |s| s["key"] }
        expect(steps["pay_merchant"]["amount"].to_f).to eq(350)
        expect(steps["pay_merchant"]["amount_direction"]).to eq("pay")
        expect(steps["collect_and_deliver"]["amount"].to_f).to eq(500)
        expect(steps["collect_and_deliver"]["amount_direction"]).to eq("collect")
      end

      it "shows what they earn and what they must advance, before anything else" do
        get "/api/v1/courier/job", headers: auth

        expect(json.dig("job", "earnings").to_f).to eq(100)
        expect(json.dig("job", "advance_required").to_f).to eq(350)
        expect(json.dig("job", "total_to_collect").to_f).to eq(500)
      end

      # LABELS ARE KEYS, not English. The server cannot write Pashto, and a
      # server-written English string is untranslatable on the device.
      it "sends i18n keys rather than English words" do
        get "/api/v1/courier/job", headers: auth

        json.dig("job", "steps").each do |step|
          expect(step["label_key"]).to match(/\Acourier\.steps\./)
        end
      end

      it "carries the landmark note, which IS the address in this market" do
        get "/api/v1/courier/job", headers: auth

        step = json.dig("job", "steps").find { |s| s["key"] == "go_to_customer" }
        expect(step["landmark_note"]).to be_present
        expect(step["phone"]).to eq(order.customer_phone)
      end

      it "carries the items, because the courier checks the bag" do
        get "/api/v1/courier/job", headers: auth

        expect(json.dig("job", "items").first["name"]).to be_present
      end
    end

    describe "a ride, as a three-step list" do
      let!(:ride) do
        trip = create(:trip, :accepted, courier: courier, fare: 160, commission: 20,
                                        courier_earnings: 140)
        trip.transitions.create!(to_status: "accepted", actor_role: :courier, created_at: Time.current)
        trip
      end

      it "serialises three steps, with no pay step at all" do
        get "/api/v1/courier/job", headers: auth

        steps = json.dig("job", "steps")
        expect(steps.map { |s| s["key"] }).to eq(%w[go_to_pickup start_ride complete_and_collect])
        expect(steps.map { |s| s["key"] }).not_to include("pay_merchant")
      end

      # The asymmetry, in the payload: a ride advances nothing.
      it "requires no advance" do
        get "/api/v1/courier/job", headers: auth

        expect(json.dig("job", "advance_required").to_f).to eq(0)
        expect(json.dig("job", "kind")).to eq("ride")
      end

      it "uses the SAME screen shape as a delivery" do
        get "/api/v1/courier/job", headers: auth

        steps = json.dig("job", "steps")
        expect(steps.first.keys).to include("key", "label_key", "location", "current", "completed")
      end
    end

    it "refuses without a token" do
      get "/api/v1/courier/job"

      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses a courier who is not approved" do
      courier.courier_profile.update!(verification_status: :pending)

      get "/api/v1/courier/job", headers: auth

      expect(response).to have_http_status(:forbidden)
      expect(json["code"]).to eq("not_approved")
    end

    it "never returns another courier's job" do
      create(:order, :picked_up, merchant: merchant)

      get "/api/v1/courier/job", headers: auth

      expect(json["job"]).to be_nil
    end
  end

  describe "POST /api/v1/courier/jobs/delivery/:id/advance" do
    let!(:order) { delivery }

    it "walks the delivery through pickup and delivery" do
      post "/api/v1/courier/jobs/delivery/#{order.id}/advance",
           params: { step_key: "pay_merchant" }, headers: auth

      expect(response).to have_http_status(:ok)
      expect(order.reload.status).to eq("picked_up")
      expect(order.merchant_paid_at).to be_present

      post "/api/v1/courier/jobs/delivery/#{order.id}/advance",
           params: { step_key: "collect_and_deliver" }, headers: auth

      expect(order.reload.status).to eq("delivered")
      expect(order.payment_status).to eq("collected")
    end

    # The money moment. Charged atomically with the transition, because a job
    # marked delivered with no commission charged is unreconcilable.
    it "charges the commission to the wallet on delivery" do
      post "/api/v1/courier/jobs/delivery/#{order.id}/advance", headers: auth

      expect { post "/api/v1/courier/jobs/delivery/#{order.id}/advance", headers: auth }
        .to change { courier.courier_wallet.reload.balance }.by(-50)

      entry = WalletEntry.where(source: order, kind: :commission).first
      expect(entry).to be_present
      expect(entry.amount).to eq(-50)
    end

    # A double-tap on a bad connection must not charge twice.
    it "charges the commission once, however many times it is called" do
      2.times { post "/api/v1/courier/jobs/delivery/#{order.id}/advance", headers: auth }
      balance = courier.courier_wallet.reload.balance

      post "/api/v1/courier/jobs/delivery/#{order.id}/advance", headers: auth

      expect(courier.courier_wallet.reload.balance).to eq(balance)
      expect(WalletEntry.where(source: order, kind: :commission).count).to eq(1)
    end

    it "records every step as a transition with the courier as the actor" do
      post "/api/v1/courier/jobs/delivery/#{order.id}/advance", headers: auth

      transition = order.reload.transitions.order(:created_at).last
      expect(transition).to have_attributes(to_status: "picked_up", actor_id: courier.id,
                                            actor_role: "courier")
    end

    # A stale screen must not advance a step the courier is not standing at.
    it "refuses a step key that is not the current one" do
      post "/api/v1/courier/jobs/delivery/#{order.id}/advance",
           params: { step_key: "collect_and_deliver" }, headers: auth

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("wrong_step")
      expect(order.reload.status).to eq("ready")
    end

    it "refuses once there is nothing left to do" do
      2.times { post "/api/v1/courier/jobs/delivery/#{order.id}/advance", headers: auth }

      post "/api/v1/courier/jobs/delivery/#{order.id}/advance", headers: auth

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("cannot_advance")
    end

    it "refuses another courier's job with a 404, not a 403 that confirms it exists" do
      other = create(:order, :ready, merchant: merchant, courier: create(:user, :courier))

      post "/api/v1/courier/jobs/delivery/#{other.id}/advance", headers: auth

      expect(response).to have_http_status(:not_found)
    end

    it "refuses an unknown job kind" do
      post "/api/v1/courier/jobs/parcel/#{order.id}/advance", headers: auth

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/courier/jobs/delivery/:id/problem" do
    let!(:order) { delivery(status: :picked_up) }

    # The platform absorbs a refusal and reimburses the courier the same day.
    # That is a money decision, so it reaches a human rather than being settled
    # by the app.
    it "fails the job with a reason and reaches admin" do
      post "/api/v1/courier/jobs/delivery/#{order.id}/problem",
           params: { reason: "customer_refused" }, headers: auth

      expect(response).to have_http_status(:ok)
      expect(order.reload.status).to eq("failed")
      expect(order.failure_reason).to eq("customer_refused")
      expect(AuditLog.where(action: "order.failed", target: order).count).to eq(1)
    end

    it "refuses a problem with no reason" do
      post "/api/v1/courier/jobs/delivery/#{order.id}/problem", headers: auth

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("reason_required")
      expect(order.reload.status).to eq("picked_up")
    end

    it "refuses an invented reason, so failures stay countable" do
      post "/api/v1/courier/jobs/delivery/#{order.id}/problem",
           params: { reason: "could not be bothered" }, headers: auth

      expect(json["code"]).to eq("reason_required")
    end

    it "offers the reason list on the active job" do
      get "/api/v1/courier/job", headers: auth

      expect(json.dig("job", "problem_reasons")).to include("customer_refused", "nobody_home")
    end
  end
end
