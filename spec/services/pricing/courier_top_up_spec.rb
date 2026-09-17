require "rails_helper"

RSpec.describe Pricing::CourierTopUp do
  let(:merchant) { create(:merchant, latitude: 34.5553, longitude: 69.2075) }
  let(:courier) { create(:user, :courier) }

  def set(key, value)
    Setting.find_or_initialize_by(key: key)
           .update!(value: value.to_s, value_type: Setting::DEFINITIONS.fetch(key)[:type])
  end

  # A thin, far order: 200 AFN of food 6 km out, a fee that pays for the drop
  # and nothing for the ride out to collect it.
  # `items_total` follows the commission rather than being fixed at 200: a
  # commission larger than the basket is not an order anybody can place, and
  # `merchant_payout` is validated non-negative. The first version of this
  # helper built one and three examples failed on the fixture rather than on
  # the code.
  def job(distance_km: 6, courier_fee: 100, commission: 25)
    items_total = [ 200, commission * 2 ].max

    create(:order, merchant: merchant, items_total: items_total, distance_km: distance_km,
                   delivery_fee: courier_fee, courier_fee: courier_fee,
                   commission: commission, merchant_payout: items_total - commission,
                   customer_total: items_total + courier_fee)
  end

  # The courier standing 4 km from the merchant — the leg nobody was paying
  # for.
  def stand_courier_away(km)
    courier.courier_profile.update!(
      last_latitude: merchant.latitude + (km / 111.0), last_longitude: merchant.longitude,
      location_updated_at: Time.current
    )
  end

  before do
    stand_courier_away(4)
    set("courier_topup_enabled", "true")
    set("courier_min_earnings_per_km", "20")
  end

  describe "the switch" do
    it "gives nothing back while it is off, which is the shipping state" do
      set("courier_topup_enabled", "false")

      expect(described_class.for(courier: courier, jobs: [ job ])).to eq({})
    end

    # The second safety: even switched on, a rate of 0 tops nothing up, so the
    # switch and the number cannot disagree into an accidental giveaway.
    it "gives nothing back at a rate of zero" do
      set("courier_min_earnings_per_km", "0")

      expect(described_class.for(courier: courier, jobs: [ job ])).to eq({})
    end
  end

  describe "what counts as the distance" do
    # THE POINT OF THE FEATURE. 6 km drop + 4 km ride out = 10 km at 20/km =
    # 200 required, against a 100 fee — 100 short, capped at the 25 commission.
    it "counts the ride OUT to the merchant, not only the drop" do
      order = job
      expect(described_class.total_km(courier: courier, jobs: [ order ]))
        .to be_within(0.2).of(10)
    end

    it "is short by the gap between the whole run and the fee" do
      expect(described_class.shortfall_for(courier: courier, jobs: [ job ]))
        .to be_within(1).of(100)
    end

    # The dead leg is the difference between this feature existing and not.
    it "is shorter for a courier already standing at the merchant" do
      stand_courier_away(0)

      expect(described_class.shortfall_for(courier: courier, jobs: [ job ]))
        .to be_within(1).of(20)
    end

    it "asks nothing back when the fee already covers the whole run" do
      expect(described_class.for(courier: courier, jobs: [ job(courier_fee: 500) ])).to eq({})
    end
  end

  describe "what it may spend" do
    # "Out of the platform's commission, down to zero, never below." The gap is
    # 100 and the commission is 25, so 25 is the answer — we give up all of our
    # margin and not a single afghani more.
    it "stops at the commission, never funding a loss" do
      order = job

      expect(described_class.for(courier: courier, jobs: [ order ])[order]).to eq(25)
    end

    it "gives back only the gap when the gap is smaller than the commission" do
      order = job(commission: 400)

      expect(described_class.for(courier: courier, jobs: [ order ])[order])
        .to be_within(1).of(100)
    end

    it "gives nothing back on an order with no commission to give" do
      expect(described_class.for(courier: courier, jobs: [ job(commission: 0) ])).to eq({})
    end
  end

  # ── CORRECTION 19: THE ARITHMETIC IS OVER A SET ──────────────────────────
  #
  # Batched, two jobs share ONE ride out. Priced per job, that leg would be
  # paid for twice — the platform funding a journey nobody took.
  describe "a batch" do
    it "counts the shared ride out once, not once per job" do
      two = [ job, job ]

      # 6 + 6 drops + ONE 4 km leg = 16, not 20.
      expect(described_class.total_km(courier: courier, jobs: two))
        .to be_within(0.3).of(16)
    end

    it "never gives back more than the whole run is short" do
      two = [ job(commission: 400), job(commission: 400) ]
      given = described_class.for(courier: courier, jobs: two)

      expect(given.values.sum)
        .to be_within(1).of(described_class.shortfall_for(courier: courier, jobs: two))
    end

    # Money split by rounding each share independently is how a minor unit gets
    # lost or invented, and `Monetary` refuses a record whose parts miss the
    # total.
    it "splits to exactly the whole, with nothing lost to rounding" do
      three = [ job(commission: 7), job(commission: 11), job(commission: 13) ]
      given = described_class.for(courier: courier, jobs: three)

      expect(given.values.sum).to eq(31)
    end

    # A batch must not fund one job's shortfall out of another job's margin.
    it "caps every job by its OWN commission" do
      jobs = [ job(commission: 5), job(commission: 400) ]
      given = described_class.for(courier: courier, jobs: jobs)

      given.each { |order, amount| expect(amount).to be <= order.commission }
    end
  end

  # This must never be the reason an assignment fails: a courier with no
  # recorded position is a courier who still has to be given the job.
  describe "when it cannot measure" do
    it "gives nothing back rather than raising, with no position" do
      courier.courier_profile.update!(last_latitude: nil, last_longitude: nil)

      expect { described_class.for(courier: courier, jobs: [ job ]) }.not_to raise_error
      expect(described_class.for(courier: courier, jobs: [ job ])).to eq({})
    end

    it "handles an empty set" do
      expect(described_class.for(courier: courier, jobs: [])).to eq({})
    end
  end
end
