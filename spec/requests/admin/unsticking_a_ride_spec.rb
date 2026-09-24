require "rails_helper"

# THE MANUAL OVERRIDE FOR A RIDE — built before any way to request one exists,
# because an operator who cannot unstick a ride leaves a passenger standing in
# the street. Driven over HTTP against a real ride in each state that matters.
RSpec.describe "an operator can unstick a ride", type: :request do
  let(:admin) { AdminUser.create!(name: "Ops", email: "ops@karwan.af", password: "a-long-test-password") }
  let(:courier) { create(:user, :ride_courier) }

  before do
    post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
  end

  describe "assigning a courier by hand" do
    # A courier's acceptance IS a ride's transition. Left at `requested` with a
    # courier, the requested timeout would cancel it as "no courier".
    it "assigns a waiting ride AND moves it to accepted, recorded as the operator's move" do
      trip = create(:trip)
      create(:offer, offerable: trip, courier: create(:user, :ride_courier))

      patch "/admin/trips/#{trip.id}/reassign", params: { courier_id: courier.id }

      trip.reload
      expect(trip).to have_attributes(courier_id: courier.id, status: "accepted")
      expect(trip.transitions.last).to have_attributes(to_status: "accepted", admin_user_id: admin.id)
      expect(trip.offers.pending).to be_empty
    end

    it "moves an accepted ride to another courier without touching its status" do
      trip = create(:trip, :accepted)

      patch "/admin/trips/#{trip.id}/reassign", params: { courier_id: courier.id }

      expect(trip.reload).to have_attributes(courier_id: courier.id, status: "accepted")
    end

    # The ride form of "after the shop is paid, this is not a reassignment".
    it "refuses once the passenger is aboard, and leaves the ride with its courier" do
      trip = create(:trip, :in_progress)
      holder = trip.courier_id

      patch "/admin/trips/#{trip.id}/reassign", params: { courier_id: courier.id }

      expect(trip.reload.courier_id).to eq(holder)
      follow_redirect!
      expect(response.body).to include("passenger is aboard")
    end
  end

  describe "cancelling" do
    it "cancels an accepted ride as the operator's decision" do
      trip = create(:trip, :accepted)

      patch "/admin/trips/#{trip.id}/cancel", params: { reason: "passenger rang" }

      expect(trip.reload).to have_attributes(status: "cancelled", cancelled_by_role: "admin")
    end

    it "refuses a ride in progress, which is failed instead" do
      trip = create(:trip, :in_progress)

      patch "/admin/trips/#{trip.id}/cancel"

      expect(trip.reload.status).to eq("in_progress")
    end
  end

  describe "failing" do
    it "fails a ride in progress with a reason from the fixed list" do
      trip = create(:trip, :in_progress)

      patch "/admin/trips/#{trip.id}/fail", params: { reason: "unsafe" }

      expect(trip.reload).to have_attributes(status: "failed", failure_reason: "unsafe")
    end

    it "demands a reason from the list" do
      trip = create(:trip, :in_progress)

      patch "/admin/trips/#{trip.id}/fail", params: { reason: "felt like it" }

      expect(trip.reload.status).to eq("in_progress")
    end
  end

  describe "redispatching" do
    it "offers a ride nobody took to the next eligible courier" do
      courier.courier_profile.update!(is_available: true, accepted_job_kinds: %w[ride], vehicle_type: :car,
                                      last_latitude: 34.54, last_longitude: 69.175, location_updated_at: Time.current)
      courier.courier_wallet.update!(balance: 1_000, credit_line: 500)
      trip = create(:trip)

      expect { patch "/admin/trips/#{trip.id}/redispatch" }.to change { trip.offers.count }.by(1)
      expect(trip.offers.last.courier).to eq(courier)
    end

    it "refuses a ride that already has a courier, and points at reassign" do
      trip = create(:trip, :accepted)

      expect { patch "/admin/trips/#{trip.id}/redispatch" }.not_to(change { trip.offers.count })
    end
  end

  # Consulted, not merely present: forced to refuse, nothing moves.
  it "consults TripPolicy: refusing it leaves the ride alone" do
    trip = create(:trip)
    allow_any_instance_of(TripPolicy).to receive(:reassign?).and_return(false)

    patch "/admin/trips/#{trip.id}/reassign", params: { courier_id: courier.id }

    expect(trip.reload.courier_id).to be_nil
  end
end
