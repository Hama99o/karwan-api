require "rails_helper"

# The order-tracking SPEC's first decision, asserted as a behaviour rather than
# a shape: a RANGE, whose WIDTH says how much we actually know.
RSpec.describe Orders::ArrivalWindow do
  include ActiveSupport::Testing::TimeHelpers

  # 6 km at the seeded 18 km/h is 20 minutes of riding, which keeps every
  # expectation below arithmetic a reader can check rather than a fixture.
  let(:merchant) { create(:merchant, latitude: 34.5400, longitude: 69.1750, prep_time_minutes: 20) }
  let(:order) { create(:order, merchant: merchant, distance_km: 6.0) }

  def window(o = order) = described_class.for(o)

  describe "the range itself" do
    # `from < to` WAS THIS EXAMPLE, AND IT COULD NOT FAIL. Planting a zero-width
    # window — `to` computed from the same instant as `from` — left it green,
    # because the outward rounding alone pushes the two onto different five-minute
    # boundaries. So it asserted the rounding, not the range.
    #
    # Wider than the rounding granularity is the claim that survives the plant:
    # rounding can manufacture at most ROUNDING_MINUTES of apparent width.
    it "is a range and never a single minute dressed up by rounding" do
      expect(window.to - window.from).to be > described_class::ROUNDING_MINUTES.minutes
    end

    it "rounds outward to five minutes, which is how a person reads an estimate" do
      expect(window.from.min % 5).to eq(0)
      expect(window.to.min % 5).to eq(0)
      expect(window.from.sec).to eq(0)
    end

    it "is never narrower than eta_window_minimum_minutes, however sure the arithmetic feels" do
      Setting.seed_defaults!
      Setting.find_by!(key: "eta_window_spread_percent_unassigned").update!(value: "0")

      expect((window.to - window.from) / 60).to be >= Setting.fetch("eta_window_minimum_minutes").to_f
    end

    it "never opens in the past, because a close courier is not a late one" do
      travel_to(Time.current) do
        near = create(:order, merchant: merchant, distance_km: 0.2)

        expect(window(near).from).to be >= Time.current - 5.minutes
        expect(window(near).from).to be <= window(near).to
      end
    end
  end

  describe "the width is the honesty" do
    let(:courier) { create(:user, :courier) }

    before do
      courier.courier_profile.update!(last_latitude: 34.5405, last_longitude: 69.1755,
                                      location_updated_at: Time.current)
      order.update!(courier: courier, status: :accepted, accepted_at: Time.current)
    end

    it "is WIDER while no courier position is known" do
      travel_to(Time.current) do
        unassigned = create(:order, merchant: merchant, distance_km: 6.0)

        assumed = window(unassigned)
        measured = window(order.reload)

        expect(assumed.basis).to eq("assumed")
        expect(measured.basis).to eq("measured")
        expect(assumed.to - assumed.from).to be > (measured.to - measured.from)
      end
    end

    it "calls a stale position assumed, because that is where he used to be" do
      courier.courier_profile.update!(location_updated_at: 2.hours.ago)

      expect(window(order.reload).basis).to eq("assumed")
    end
  end

  describe "what is still ahead depends on the state" do
    it "drops when the food is in the bag, because the kitchen and the ride to it are spent" do
      travel_to(Time.current) do
        waiting = create(:order, merchant: merchant, distance_km: 6.0, status: :preparing,
                                 accepted_at: Time.current, preparing_at: Time.current)
        carrying = create(:order, merchant: merchant, distance_km: 6.0, status: :picked_up,
                                  accepted_at: 20.minutes.ago, ready_at: 1.minute.ago,
                                  picked_up_at: Time.current)

        expect(window(carrying).to).to be < window(waiting).to
      end
    end

    it "counts the kitchen down as it cooks" do
      travel_to(Time.current) do
        just_started = create(:order, merchant: merchant, distance_km: 6.0, status: :preparing,
                                      accepted_at: Time.current, preparing_at: Time.current)
        nearly_done = create(:order, merchant: merchant, distance_km: 6.0, status: :preparing,
                                     accepted_at: 18.minutes.ago, preparing_at: 18.minutes.ago)

        expect(window(nearly_done).to).to be < window(just_started).to
      end
    end

    it "stops counting the kitchen once the shop says ready" do
      travel_to(Time.current) do
        ready = create(:order, merchant: merchant, distance_km: 6.0, status: :ready,
                               accepted_at: 5.minutes.ago, ready_at: Time.current)
        cooking = create(:order, merchant: merchant, distance_km: 6.0, status: :preparing,
                                 accepted_at: 5.minutes.ago, preparing_at: 5.minutes.ago)

        expect(window(ready).to).to be < window(cooking).to
      end
    end
  end

  describe "what it refuses to answer" do
    it "is nil on a terminal order — there is no arrival to estimate" do
      %i[delivered cancelled failed].each do |state|
        expect(window(create(:order, state, merchant: merchant, distance_km: 6.0))).to be_nil
      end
    end

    it "is nil when the distance was never measured, rather than inventing one" do
      expect(window(create(:order, merchant: merchant, distance_km: nil))).to be_nil
    end
  end

  # MAP_AND_ROUTING.md: a fare must be explainable later, and an explanation
  # that re-measures is not an explanation of what was charged. So the window
  # and the price are answers about the same journey.
  it "never re-measures the frozen merchant-to-customer leg" do
    travel_to(Time.current) do
      before_move = window(order)
      merchant.update!(latitude: 34.9000, longitude: 69.9000)

      expect(window(order.reload).to).to eq(before_move.to)
    end
  end
end
