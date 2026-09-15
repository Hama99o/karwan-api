require "rails_helper"

RSpec.describe Dispatch::Eligibility do
  let(:courier) { create(:user, :courier) }
  let(:order) do
    create(:order, items_total: 400, delivery_fee: 100, customer_total: 500,
                   commission: 50, merchant_payout: 350)
  end

  def eligibility(job = order, for_courier: courier)
    described_class.new(courier: for_courier, job: job)
  end

  before do
    courier.courier_profile.update!(is_available: true, last_latitude: 34.5553,
                                    last_longitude: 69.2075, location_updated_at: Time.current)
    courier.courier_wallet.update!(balance: 1_000, credit_line: 500)
  end

  it "is eligible when everything is in order" do
    expect(eligibility).to be_eligible
    expect(eligibility.reason).to be_nil
  end

  # Returns the REASON rather than a bare boolean, because "no couriers
  # available" is the least useful sentence in an ops console. Every one of
  # these is a different problem with a different fix.
  describe "each independent reason" do
    it "names a missing profile" do
      expect(eligibility(for_courier: create(:user)).reason).to eq(:no_profile)
    end

    it "names an unapproved courier" do
      courier.courier_profile.update!(verification_status: :pending)

      expect(eligibility.reason).to eq(:not_approved)
    end

    it "names a courier off shift" do
      courier.courier_profile.update!(is_available: false)

      expect(eligibility.reason).to eq(:off_shift)
    end

    it "names a courier who does not take this kind of job" do
      expect(eligibility(create(:trip)).reason).to eq(:wrong_job_kind)
    end

    # Dispatch is distance-based, so a fix we cannot trust is a dispatch we
    # cannot make. Better to skip this courier than to send the nearest
    # courier-shaped memory.
    it "names a stale position" do
      courier.courier_profile.update!(location_updated_at: 1.hour.ago)

      expect(eligibility.reason).to eq(:stale_location)
    end

    it "names a blocked wallet" do
      courier.courier_wallet.update!(balance: -500, credit_line: 500)

      expect(eligibility.reason).to eq(:wallet_blocked)
    end

    it "names a wallet that cannot cover the advance" do
      courier.courier_wallet.update!(balance: -200, credit_line: 500)

      expect(eligibility.reason).to eq(:insufficient_credit)
    end

    # The gap this closed: `cash_in_hand_limit` existed as a Setting promising
    # exactly this behaviour, and nothing read it.
    it "names too much of our cash in hand" do
      Setting.seed_defaults!
      Setting.find_by!(key: "cash_in_hand_limit").update!(value: "100")
      create(:order, :delivered, courier: courier, commission: 150)

      expect(eligibility.reason).to eq(:cash_in_hand)
    end

    it "gives every reason a human explanation" do
      described_class::REASONS.each_value { |text| expect(text).to be_present }
    end

    it "explains the reason it returns" do
      courier.courier_profile.update!(is_available: false)

      expect(eligibility.explanation).to eq(described_class::REASONS[:off_shift])
    end
  end

  # The asymmetry that matters: a courier too short for a delivery can still
  # earn on a ride, because a ride advances nothing.
  describe "the two demand types gate differently" do
    it "refuses the delivery but allows the ride on the same wallet" do
      courier.courier_profile.update!(accepted_job_kinds: %w[delivery ride])
      courier.courier_wallet.update!(balance: -200, credit_line: 500)
      ride = create(:trip, fare: 160, commission: 20, courier_earnings: 140)

      expect(eligibility(order).reason).to eq(:insufficient_credit)
      expect(eligibility(ride)).to be_eligible
    end
  end

  describe "ordering of reasons" do
    # Approval before availability, both before money, so an operator is told
    # the most fundamental problem rather than a symptom of it.
    it "reports the most fundamental problem first" do
      courier.courier_profile.update!(verification_status: :pending, is_available: false)
      courier.courier_wallet.update!(balance: -500, credit_line: 500)

      expect(eligibility.reason).to eq(:not_approved)
    end
  end
end
