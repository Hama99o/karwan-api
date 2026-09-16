require "rails_helper"

RSpec.describe "Api::V1::Couriers::Offers", type: :request do
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

  def delivery(status: :ready, assigned_to: nil)
    create(:order, :with_items, status, merchant: merchant, courier: assigned_to,
                                        items_total: 400, delivery_fee: 100,
                                        customer_total: 500, commission: 50,
                                        courier_fee: 100, merchant_payout: 350)
  end

  describe "POST /api/v1/courier/offers/:id/accept" do
    it "assigns the job to a free courier" do
      offer = create(:offer, courier: courier, offerable: delivery)

      post "/api/v1/courier/offers/#{offer.id}/accept", headers: auth

      expect(response).to have_http_status(:ok)
      expect(offer.reload).to be_status_accepted
      expect(offer.offerable.reload.courier).to eq(courier)
    end

    # ── THE DOUBLE-BOOKING REFUSAL ───────────────────────────────────────────
    #
    # The eligibility check alone is not enough, and this is why: eligibility
    # runs when an offer is MADE. A courier holding an offer made a minute ago
    # could take other work and then accept this one, and nothing in the accept
    # path refused him. The refusal has to live here too.
    context "when the courier is already carrying a job" do
      it "refuses a RIDE offer while a delivery is in his box" do
        delivery(status: :picked_up, assigned_to: courier)
        offer = create(:offer, courier: courier, offerable: create(:trip))

        post "/api/v1/courier/offers/#{offer.id}/accept", headers: auth

        expect(response).to have_http_status(:unprocessable_content)
        expect(json["code"]).to eq("already_on_a_job")
        expect(json["error"]).to eq("courier is already carrying a job")
      end

      it "refuses a second DELIVERY offer" do
        delivery(status: :picked_up, assigned_to: courier)
        offer = create(:offer, courier: courier, offerable: delivery)

        post "/api/v1/courier/offers/#{offer.id}/accept", headers: auth

        expect(response).to have_http_status(:unprocessable_content)
        expect(json["code"]).to eq("already_on_a_job")
      end

      # A refusal must leave the offer answerable. Consumed here, the courier
      # would be left holding a dead card he can neither accept nor decline,
      # and the job would sit until the expiry sweep re-offered it.
      it "leaves the offer and the job untouched" do
        delivery(status: :picked_up, assigned_to: courier)
        trip = create(:trip)
        offer = create(:offer, courier: courier, offerable: trip)

        post "/api/v1/courier/offers/#{offer.id}/accept", headers: auth

        expect(offer.reload).to be_status_offered
        expect(trip.reload.courier).to be_nil
        expect(trip.reload.status).to eq("requested")
      end

      # And nobody else's offer on that job may be superseded by a refused
      # accept — that would starve the job of the courier who could take it.
      it "does not supersede the other couriers' offers on that job" do
        delivery(status: :picked_up, assigned_to: courier)
        trip = create(:trip)
        offer = create(:offer, courier: courier, offerable: trip)
        rival = create(:offer, courier: create(:user, :ride_courier), offerable: trip)

        post "/api/v1/courier/offers/#{offer.id}/accept", headers: auth

        expect(rival.reload).to be_status_offered
      end
    end

    # ── THE RACE ─────────────────────────────────────────────────────────────
    #
    # Two taps arriving together — two phones, or one phone retrying on a bad
    # connection — can both pass the check ABOVE the transaction and both
    # assign. The guard against that is the row lock plus a re-check INSIDE
    # the transaction, and this is the only test that can tell the two checks
    # apart: it makes the competing work appear after the outer check has
    # already passed.
    #
    # What is stubbed is `lock!` — the moment another request would land — and
    # it still calls through, so the lock really is taken. The real
    # `Dispatch::Eligibility` runs both times. Nothing stands in for the
    # subject; only the timing is injected, because wall-clock timing is the
    # one thing a single-threaded spec cannot produce.
    it "refuses work that appeared between the outer check and the lock" do
      offer = create(:offer, courier: courier, offerable: create(:trip))
      competing = nil

      allow_any_instance_of(User).to receive(:lock!).and_wrap_original do |original, *args|
        competing ||= delivery(status: :picked_up, assigned_to: courier)
        original.call(*args)
      end

      post "/api/v1/courier/offers/#{offer.id}/accept", headers: auth

      expect(competing).to be_present, "the competing job was never created — the spec proved nothing"
      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("already_on_a_job")
      expect(offer.reload).to be_status_offered
      expect(offer.offerable.reload.courier).to be_nil
    end
  end
end
