require "rails_helper"

# ONE HUMAN, ONE VEHICLE, ONE PLACE AT A TIME.
#
# `Dispatch::Eligibility` had nine checks and none of them asked whether the
# courier was already carrying a job. So a courier riding to a customer with a
# meal in his box could be offered a TRIP and accept it, and nothing refused
# him. One of those two customers then loses for certain — food going cold
# while he drives a passenger across Kabul, or a passenger at a kerb while he
# finishes the delivery.
#
# It spans BOTH tables on purpose. The utilisation thesis is one courier pool
# serving two demand streams, so "already busy" is only true if you look at
# delivery AND ride.
RSpec.describe "one live job per courier" do
  let(:courier) { create(:user, :courier) }
  let(:merchant) { create(:merchant, latitude: 34.5553, longitude: 69.2075) }

  before do
    courier.courier_profile.update!(
      verification_status: :approved, is_available: true,
      accepted_job_kinds: %w[delivery ride],
      last_latitude: 34.5553, last_longitude: 69.2075, location_updated_at: Time.current
    )
    courier.courier_wallet.update!(balance: 10_000, credit_line: 500)
  end

  def reason_for(job)
    Dispatch::Eligibility.new(courier: courier, job: job).reason
  end

  it "offers a free courier work" do
    expect(reason_for(create(:order, :ready, merchant: merchant))).to be_nil
  end

  describe "while carrying a DELIVERY" do
    before { create(:order, :picked_up, merchant: merchant, courier: courier) }

    # The exact case that was possible: a meal in his box, and a ride offered.
    it "refuses a RIDE — the case that could double-book him" do
      expect(reason_for(create(:trip))).to eq(:already_on_a_job)
    end

    it "refuses another delivery" do
      expect(reason_for(create(:order, :ready, merchant: merchant))).to eq(:already_on_a_job)
    end

    it "explains itself, so an ops console can say why work went unassigned" do
      eligibility = Dispatch::Eligibility.new(courier: courier, job: create(:trip))

      expect(eligibility).not_to be_eligible
      expect(eligibility.explanation).to eq("courier is already carrying a job")
    end
  end

  describe "while carrying a RIDE" do
    before { create(:trip, :in_progress, courier: courier) }

    it "refuses a delivery — the mirror case" do
      expect(reason_for(create(:order, :ready, merchant: merchant))).to eq(:already_on_a_job)
    end
  end

  describe "once the job is over" do
    # A courier must be dispatchable again the moment he is free, or the pool
    # drains over an evening and the whole utilisation argument fails.
    it "offers him work again after a delivery is delivered" do
      create(:order, :delivered, merchant: merchant, courier: courier)

      expect(reason_for(create(:trip))).to be_nil
    end

    it "offers him work again after a job FAILS, not just after it succeeds" do
      create(:order, :failed, merchant: merchant, courier: courier)

      expect(reason_for(create(:order, :ready, merchant: merchant))).to be_nil
    end

    it "offers him work again after a cancellation" do
      create(:trip, :cancelled, courier: courier)

      expect(reason_for(create(:order, :ready, merchant: merchant))).to be_nil
    end
  end

  # An admin reassigning the SAME job to the same courier must not be refused
  # as a conflict with itself — that is a refusal nobody could explain.
  it "does not treat a re-offer of the job he already holds as a conflict" do
    held = create(:order, :picked_up, merchant: merchant, courier: courier)

    expect(reason_for(held)).to be_nil
  end

  # Placed above the wallet checks: it is the cheapest query and the commonest
  # reason to skip a courier on a busy evening.
  it "reports being busy BEFORE reporting an empty wallet" do
    create(:order, :picked_up, merchant: merchant, courier: courier)
    courier.courier_wallet.update!(balance: -500, credit_line: 500)

    expect(reason_for(create(:order, :ready, merchant: merchant))).to eq(:already_on_a_job)
  end
end
