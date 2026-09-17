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

    # ── THE DEAD LEG IS PRICED AT ASSIGNMENT, BECAUSE THAT IS WHEN IT EXISTS ─
    #
    # The leg is courier→merchant, so at quote time — the cart — there is no
    # courier to measure from. Frozen onto the row here like every other
    # amount, and it moves nothing the customer was quoted: it shifts money
    # from our commission to the courier.
    context "the distance top-up" do
      def set(key, value)
        Setting.find_or_initialize_by(key: key)
               .update!(value: value.to_s, value_type: Setting::DEFINITIONS.fetch(key)[:type])
      end

      before do
        set("courier_topup_enabled", "true")
        set("courier_min_earnings_per_km", "20")
      end

      # A courier 4 km out, a 6 km drop: 10 km of riding for a fee priced on the
      # drop alone.
      def far_from_the_merchant(order)
        order.update!(distance_km: 6)
        courier.courier_profile.update!(last_latitude: merchant.latitude + 0.036,
                                        last_longitude: merchant.longitude,
                                        location_updated_at: Time.current)
      end

      it "freezes what we are giving back onto the order" do
        order = delivery
        far_from_the_merchant(order)
        offer = create(:offer, courier: courier, offerable: order)

        post "/api/v1/courier/offers/#{offer.id}/accept", headers: auth
        order.reload

        expect(response).to have_http_status(:ok)
        expect(order.commission_topup).to be > 0
        expect(order.commission_topup)
          .to eq((Setting.fetch("courier_min_earnings_per_km") *
                  Pricing::CourierTopUp.total_km(courier: courier, jobs: [ order ]) -
                  order.courier_fee).round(2))
      end

      # ── THE ORDERING IS LOAD-BEARING ────────────────────────────────────────
      #
      # Assigning the courier is what sets `courier_fee` from HIS vehicle's
      # rate — the assignment freeze point. So the top-up must be computed
      # AFTER that line, against the fee he is actually paid, not against the
      # placeholder the order was created with.
      #
      # This example is written as the difference between the two, because it
      # is the only way to tell them apart: it asserts the top-up matches the
      # POST-assignment fee and would not match the pre-assignment one.
      it "measures the shortfall against the fee the courier is actually paid" do
        order = delivery
        far_from_the_merchant(order)
        # A commission big enough that the cap does NOT bind. Without this the
        # example is vacuous: both the right answer and the wrong one get
        # clamped to the commission and compare equal, which is how the first
        # version of it passed against a planted bug.
        order.update!(items_total: 900, commission: 400, merchant_payout: 500,
                      customer_total: 900 + order.delivery_fee)
        fee_before = order.courier_fee
        offer = create(:offer, courier: courier, offerable: order)

        post "/api/v1/courier/offers/#{offer.id}/accept", headers: auth
        order.reload

        # The vehicle rate moved the fee; if it ever stops doing so this
        # example is no longer testing anything and should be deleted rather
        # than left to pass vacuously.
        expect(order.courier_fee).not_to eq(fee_before)

        naive = (Setting.fetch("courier_min_earnings_per_km") *
                 Pricing::CourierTopUp.total_km(courier: courier, jobs: [ order ]) -
                 fee_before).round(2)
        expect(order.commission_topup).not_to eq(naive)
      end

      it "changes nothing the customer was quoted" do
        order = delivery
        order.update!(distance_km: 6)
        offer = create(:offer, courier: courier, offerable: order)

        expect { post "/api/v1/courier/offers/#{offer.id}/accept", headers: auth }
          .not_to change { order.reload.slice(:customer_total, :delivery_fee, :merchant_payout) }
      end

      it "freezes nothing while the switch is off" do
        set("courier_topup_enabled", "false")
        order = delivery
        order.update!(distance_km: 6)
        offer = create(:offer, courier: courier, offerable: order)

        post "/api/v1/courier/offers/#{offer.id}/accept", headers: auth

        expect(order.reload.commission_topup).to eq(0)
      end

      # It must never be the reason a courier cannot take a job.
      it "still assigns the job when there is no position to measure from" do
        courier.courier_profile.update!(last_latitude: nil, last_longitude: nil)
        offer = create(:offer, courier: courier, offerable: delivery)

        post "/api/v1/courier/offers/#{offer.id}/accept", headers: auth

        expect(response).to have_http_status(:ok)
        expect(offer.reload.offerable.courier).to eq(courier)
      end
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
