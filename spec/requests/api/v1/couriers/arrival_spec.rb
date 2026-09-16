require "rails_helper"

# "I AM AT THE GATE." The arrival moment Hamma9900 asked about.
#
# He asked for customer and courier to reach each other especially then, and
# offered a chat. **A notification is what actually solves it:** a message
# inside the app reaches somebody who has the app open, and a person waiting
# for a delivery does not — they are in the kitchen, or on another floor, or on
# a phone somebody else is using. The tappable number is the fallback, and it
# needs no data at all.
RSpec.describe "Api::V1::Couriers arrival", type: :request do
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
  end

  def delivery(status: :picked_up, assigned: courier)
    create(:order, :with_items, status, merchant: merchant, courier: assigned, distance_km: 3.0)
  end

  describe "a delivery" do
    it "records the arrival and tells the customer" do
      order = delivery

      expect { post "/api/v1/courier/jobs/delivery/#{order.id}/arrived", headers: auth }
        .to have_enqueued_job(Notifications::ArrivalAlertJob).with("Order", order.id)

      expect(response).to have_http_status(:ok)
      expect(json["announced"]).to be true
      expect(order.reload.courier_arrived_at).to be_present
    end

    # IT MOVES NOTHING. The order is `picked_up` before and after — what
    # changes is that somebody was told.
    it "does not move the order's status" do
      order = delivery

      post "/api/v1/courier/jobs/delivery/#{order.id}/arrived", headers: auth

      expect(order.reload.status).to eq("picked_up")
    end

    # A courier taps one-handed, in sunlight, wearing a glove — and retries on
    # a bad connection. A second tap must not ring the customer again.
    it "is idempotent, and says so without failing" do
      order = delivery
      post "/api/v1/courier/jobs/delivery/#{order.id}/arrived", headers: auth
      first_time = order.reload.courier_arrived_at

      expect { post "/api/v1/courier/jobs/delivery/#{order.id}/arrived", headers: auth }
        .not_to have_enqueued_job(Notifications::ArrivalAlertJob)

      expect(response).to have_http_status(:ok)
      expect(json["announced"]).to be false
      expect(order.reload.courier_arrived_at).to eq(first_time)
    end

    # Announcing arrival before collecting the food would tell a customer to
    # come down to nobody.
    it "refuses before the food has been collected" do
      order = delivery(status: :ready)

      post "/api/v1/courier/jobs/delivery/#{order.id}/arrived", headers: auth

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("too_early_to_arrive")
      expect(order.reload.courier_arrived_at).to be_nil
    end

    # A 404 RATHER THAN A 403, and that is the better answer: the lookup is
    # already scoped to this courier's own jobs, so another courier's job is
    # not refused — it does not exist as far as this request is concerned, and
    # a 403 would confirm that it does.
    #
    # The service's own `NotYourJob` guard still matters: it is what protects a
    # console session, a script or a future endpoint that resolves a job any
    # other way. It is tested at the service, not here.
    it "cannot see somebody else's job at all" do
      order = delivery(assigned: create(:user, :courier))

      post "/api/v1/courier/jobs/delivery/#{order.id}/arrived", headers: auth

      expect(response).to have_http_status(:not_found)
      expect(order.reload.courier_arrived_at).to be_nil
    end
  end

  describe "a ride" do
    # A RIDE ALREADY HAD A STATE FOR THIS, because a passenger who is not at
    # the kerb is the whole problem of a taxi. The state machine owns the
    # transition; this action just also tells them.
    it "moves the trip to arrived, through the state machine" do
      trip = create(:trip, :accepted, courier: courier)

      expect { post "/api/v1/courier/jobs/ride/#{trip.id}/arrived", headers: auth }
        .to have_enqueued_job(Notifications::ArrivalAlertJob).with("Trip", trip.id)

      expect(trip.reload.status).to eq("arrived")
      expect(trip.arrived_at).to be_present
    end

    it "leaves a history row, so the gap is not where somebody looks" do
      trip = create(:trip, :accepted, courier: courier)

      post "/api/v1/courier/jobs/ride/#{trip.id}/arrived", headers: auth

      expect(trip.transitions.where(to_status: "arrived")).to be_present
    end

    it "is idempotent for a trip already marked arrived" do
      trip = create(:trip, :arrived, courier: courier)

      expect { post "/api/v1/courier/jobs/ride/#{trip.id}/arrived", headers: auth }
        .not_to have_enqueued_job(Notifications::ArrivalAlertJob)

      expect(json["announced"]).to be false
    end
  end

  it "refuses without a token" do
    order = delivery

    post "/api/v1/courier/jobs/delivery/#{order.id}/arrived"

    expect(response).to have_http_status(:unauthorized)
    expect(order.reload.courier_arrived_at).to be_nil
  end

  # The service guard, tested where it lives — because the HTTP path can never
  # reach it and a guard nothing exercises is a guard nobody can trust.
  describe "the service's own ownership check" do
    it "refuses a job that is not this courier's" do
      order = delivery(assigned: create(:user, :courier))

      expect { Couriers::AnnounceArrivalService.new(job: order, courier: courier).call }
        .to raise_error(Couriers::AnnounceArrivalService::NotYourJob)
    end
  end
end
