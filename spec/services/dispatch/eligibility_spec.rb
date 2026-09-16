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

    # ── HOW FAR IS TOO FAR TO ASK ───────────────────────────────────────────
    #
    # `OfferService` picks the NEAREST eligible courier, which with no ceiling
    # silently means "however far away he is". In one Kabul neighbourhood that
    # never bites; the day a second city exists, a Kabul order is offered to a
    # Jalalabad courier who accepts in good faith and then rides 150km or
    # cancels — and the only party who could have known is us.
    #
    # The courier in these examples is OTHERWISE PERFECTLY ELIGIBLE. That is
    # the point: the distance has to be the only thing standing between him and
    # the job, or the example proves nothing about the ceiling.
    describe "the offer radius" do
      # Shar-e-Naw. The merchant the order is created against sits here too, so
      # the baseline distance is ~0 and every number below is deliberate.
      let(:pickup) { [ 34.5553, 69.2075 ] }

      def put_courier_km_away(km)
        # ~0.009 degrees of latitude is a kilometre. North, so longitude
        # scaling by latitude does not come into it.
        courier.courier_profile.update!(
          last_latitude: pickup[0] + (km * 0.009), last_longitude: pickup[1],
          location_updated_at: Time.current
        )
      end

      before do
        order.merchant.update!(latitude: pickup[0], longitude: pickup[1])
      end

      it "asks a courier who is comfortably inside it" do
        put_courier_km_away(3)

        expect(eligibility.reason).to be_nil
      end

      it "REFUSES one who is otherwise perfect but too far" do
        put_courier_km_away(20)

        expect(eligibility.reason).to eq(:too_far)
      end

      # The failure this exists to prevent, at the distance that makes it
      # concrete rather than theoretical.
      it "refuses a courier in another city" do
        # Jalalabad is ~120km east of Kabul.
        courier.courier_profile.update!(last_latitude: 34.4415, last_longitude: 70.4515,
                                        location_updated_at: Time.current)

        expect(eligibility.reason).to eq(:too_far)
      end

      it "follows the Setting rather than a constant, so Hamma9900 can retune it" do
        put_courier_km_away(20)
        Setting.find_or_initialize_by(key: "dispatch_max_offer_radius_km")
               .update!(value: "50", value_type: :decimal)

        expect(eligibility.reason).to be_nil
      end

      # ── ORDERED AFTER FRESHNESS, AND THAT ORDER IS LOAD-BEARING ───────────
      #
      # A distance computed from a position we do not trust is worse than no
      # distance: it would reject a courier on the strength of where he was an
      # hour ago, and report the wrong reason for it.
      it "says the position is STALE, not that he is far, when both are true" do
        courier.courier_profile.update!(last_latitude: 34.4415, last_longitude: 70.4515,
                                        location_updated_at: 1.hour.ago)

        expect(eligibility.reason).to eq(:stale_location)
      end

      # ── FAILS OPEN ON A MISSING PICKUP ───────────────────────────────────
      #
      # A job with no pickup point cannot be dispatched at all — `OfferService`
      # returns early on exactly that — so answering "too far" here would put a
      # misleading reason on the admin board for a job whose real problem is a
      # missing address.
      it "does not blame the distance when the job has no pickup point" do
        order.merchant.update!(latitude: nil, longitude: nil)

        expect(eligibility.reason).not_to eq(:too_far)
      end
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
