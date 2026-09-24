require "rails_helper"

# ── RIDES HAVE NO FRONT DOOR YET. THE MACHINERY UNDER THEM MUST STILL WORK ──
#
# Nothing in app/ creates a Trip, and no app screen shows one: rides are
# built and switched off. So nothing exercises them daily, and every fix of
# 24 Sept 2026 came through the food path. This walks one ride through the
# SHARED machinery those fixes live in — dispatch (and its lock), the locked
# transition, the courier's steps, the commission, the cash he holds, and
# settlement — so the day a ride door is built, what is under it is known to
# work rather than assumed to. What must come WITH the door is
# docs/NOTES.md, "THE RIDE DOOR — build it from this list".
RSpec.describe "a ride through the shared machinery" do
  let(:courier) { create(:user, :courier) }
  let(:trip) { create(:trip, fare: 160, commission: 20, courier_earnings: 140) }

  before do
    courier.courier_profile.update!(is_available: true, accepted_job_kinds: %w[ride], vehicle_type: :car,
                                    last_latitude: 34.5553, last_longitude: 69.2075,
                                    location_updated_at: Time.current)
    courier.courier_wallet.update!(balance: 1_000, credit_line: 500)
  end

  def dispatch_and_accept
    offer = Dispatch::OfferService.new(trip).call
    expect(offer&.courier).to eq(courier)
    offer.respond!(:accepted)
    trip.update!(courier: courier)
    expect(trip.transition_to!(:accepted, actor: courier, actor_role: :courier)).to be(true)
  end

  def ride_to_the_end
    Couriers::JobSteps.new(trip.reload).call.map { |step| step[:key] }.each do |key|
      Couriers::AdvanceJobService.new(job: trip.reload, courier: courier, step_key: key).call
    end
    trip.reload
  end

  it "is offered, accepted, driven and completed with the fare collected" do
    dispatch_and_accept
    ride_to_the_end

    expect(trip).to have_attributes(status: "completed", payment_status: "collected")
  end

  it "charges the commission once, and counts the cash he now holds of ours" do
    dispatch_and_accept

    expect { ride_to_the_end }.to change { courier.courier_wallet.reload.balance }.by(-20)
    expect(WalletEntry.where(source: trip, kind: :commission).count).to eq(1)
    expect(Couriers::CashPosition.new(courier).held).to eq(20)
  end

  it "records where the courier was when he arrived" do
    dispatch_and_accept
    ride_to_the_end

    expect(trip.transitions.where(actor_role: "courier").where.not(courier_latitude: nil)).to exist
  end

  it "is covered by the offer lock: a second dispatch of the same ride offers nobody else" do
    Dispatch::OfferService.new(trip).call
    create(:user, :courier).tap do |other|
      other.courier_profile.update!(is_available: true, accepted_job_kinds: %w[ride], vehicle_type: :car,
                                    last_latitude: 34.5554, last_longitude: 69.2075, location_updated_at: Time.current)
      other.courier_wallet.update!(balance: 1_000, credit_line: 500)
    end

    expect(Dispatch::OfferService.new(trip).call).to be_nil
    expect(trip.offers.pending.count).to eq(1)
  end
end
