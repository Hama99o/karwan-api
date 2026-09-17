require "rails_helper"

RSpec.describe Pricing::DeliveryQuote do
  let(:merchant) do
    create(:merchant, latitude: 34.5400, longitude: 69.1750,
                      commission_rate: 0.125, prep_time_minutes: 20)
  end

  def quote(items_total: 400, lat: 34.5658, lng: 69.2123, service_tier: :normal)
    described_class.new(merchant: merchant, items_total: items_total,
                        delivery_latitude: lat, delivery_longitude: lng,
                        service_tier: service_tier).call
  end

  def set(key, value)
    Setting.find_or_initialize_by(key: key)
           .update!(value: value.to_s, value_type: Setting::DEFINITIONS.fetch(key)[:type])
  end

  def storm(multiplier)
    set("shortage_multiplier", multiplier)
    set("shortage_multiplier_enabled", "true")
  end

  describe "the simple distance formula" do
    # base 50 + 20/km, derived from the actual distance rather than from a
    # hand-computed number, so the example tests the code and not my arithmetic.
    it "charges base plus per-kilometre" do
      result = quote
      km = BigDecimal(result.distance_km.to_s)

      expected = Setting.fetch("delivery_base_fee") + (Setting.fetch("delivery_fee_per_km") * km)

      expect(result.distance_km).to be_within(0.5).of(4.3)
      expect(result.amounts[:delivery_fee]).to eq(expected.round(2))
    end

    # The floor is what makes a 200-metre order worth taking at all.
    it "applies the minimum on a very short delivery" do
      result = quote(lat: 34.5401, lng: 69.1751)

      expect(result.amounts[:delivery_fee]).to eq(Setting.fetch("delivery_minimum_fee"))
    end

    it "charges more for a longer delivery" do
      near = quote(lat: 34.5420, lng: 69.1770).amounts[:delivery_fee]
      far = quote(lat: 34.6200, lng: 69.3000).amounts[:delivery_fee]

      expect(far).to be > near
    end

    # Every input is a Setting row precisely so the market can be tested by
    # editing numbers rather than deploying.
    it "follows the settings when they change, with no code change" do
      before = quote.amounts[:delivery_fee]
      Setting.seed_defaults!
      Setting.find_by!(key: "delivery_fee_per_km").update!(value: "40.0")

      expect(quote.amounts[:delivery_fee]).to be > before
    end
  end

  describe "the money identities" do
    it "takes the MERCHANT's own commission rate, not the global one" do
      merchant.update!(commission_rate: 0.2)

      expect(quote.amounts[:commission]).to eq(80)
    end

    it "pays the merchant the items less our commission" do
      amounts = quote.amounts

      expect(amounts[:merchant_payout]).to eq(amounts[:items_total] - amounts[:commission])
    end

    it "charges the customer the items plus the delivery fee" do
      amounts = quote.amounts

      expect(amounts[:customer_total]).to eq(amounts[:items_total] + amounts[:delivery_fee])
    end

    it "gives the courier the whole delivery fee in v0" do
      amounts = quote.amounts

      expect(amounts[:courier_fee]).to eq(amounts[:delivery_fee])
    end

    # The quote has to produce an order the model will accept. A price the
    # database refuses is not a price.
    it "produces amounts an Order accepts, including the totals validation" do
      customer = create(:user, :customer)
      result = quote

      order = Order.new(
        result.to_attributes.merge(
          customer: customer, merchant: merchant,
          delivery_latitude: 34.5658, delivery_longitude: 69.2123,
          customer_phone: customer.phone, payment_method: :cash, placed_at: Time.current
        )
      )

      expect(order).to be_valid, order.errors.full_messages.join("; ")
    end

    it "returns BigDecimal amounts, never Float" do
      quote.amounts.each_value { |amount| expect(amount).to be_a(BigDecimal) }
    end
  end

  describe "duration" do
    # A customer waiting for food does not care which half of the wait is
    # cooking. Quoting only the ride makes every order look late.
    it "includes the kitchen as well as the travel" do
      travel_only = Geo::Distance.travel_minutes(quote.distance_km)

      expect(quote.duration_minutes).to eq(travel_only + 20)
    end

    it "adds nothing for a merchant that does not prepare food" do
      store = create(:merchant, :store, latitude: 34.5400, longitude: 69.1750)
      result = described_class.new(merchant: store, items_total: 600,
                                   delivery_latitude: 34.5658, delivery_longitude: 69.2123).call

      expect(result.duration_minutes).to eq(Geo::Distance.travel_minutes(result.distance_km))
    end
  end

  describe "failure" do
    # Raising beats returning a zero-distance quote, which would charge the
    # minimum fee for a job of unknown length.
    it "refuses to price a delivery from a merchant with no location" do
      merchant.update_columns(latitude: nil, longitude: nil)

      expect { quote }.to raise_error(described_class::Error, /no location/)
    end
  end

  # ── THE MANUAL SHORTAGE SWITCH ──────────────────────────────────────────
  #
  # Hamma9900's condition for this being legitimate rather than gouging: it
  # raises the customer's fee AND the courier's pay together. The examples
  # below assert that as a PROPERTY of the money rather than as two numbers,
  # because the numbers are settings he retunes.
  describe "a shortage" do
    it "changes nothing while nobody has turned it on" do
      expect(quote.amounts[:delivery_fee]).to eq(quote.amounts[:courier_fee])
      expect(quote.shortage_multiplier).to eq(1)
    end

    it "raises what the customer pays AND what the courier is paid" do
      calm = quote.amounts
      storm("1.5")
      wild = quote.amounts

      expect(wild[:delivery_fee]).to eq((calm[:delivery_fee] * BigDecimal("1.5")).round(2))
      expect(wild[:courier_fee]).to eq((calm[:courier_fee] * BigDecimal("1.5")).round(2))
    end

    # THE POINT OF THE WHOLE FEATURE, stated as the thing that must not happen:
    # the customer pays more because the COURIER is paid more, not because we
    # are. On a normal-tier order the platform's cut of the delivery is zero
    # before and zero after — we do not profit from the storm.
    # NOTE THE SECOND ASSERTION, and it is the one that makes this an example
    # rather than a decoration. "The two sides are equal" is also true when
    # NEITHER of them moved — planting `courier_fee = base_delivery_fee` left
    # this green, because the customer's fee is derived from the courier's. So
    # it has to say the storm arrived as well as that we did not keep it.
    it "does not put a single afghani of the storm in our pocket" do
      calm = quote.amounts
      storm("1.8")
      amounts = quote.amounts

      expect(amounts[:delivery_fee]).to be > calm[:delivery_fee]
      expect(amounts[:delivery_fee] - amounts[:courier_fee]).to eq(0)
    end

    it "is frozen onto the quote, both what was applied and what was asked" do
      storm("1.5")

      expect(quote.shortage_multiplier).to eq(BigDecimal("1.5"))
      expect(quote.shortage_multiplier_requested).to eq(BigDecimal("1.5"))
    end
  end

  # base → shortage → tier. The order is a product decision and this is what it
  # buys: premium is ALWAYS exactly +30% over the same run, storm or no storm,
  # which is the property that makes an upfront fare explainable to a customer.
  describe "a shortage and a premium together" do
    it "keeps premium at exactly the premium multiplier over the same run" do
      set("premium_price_multiplier", "1.3")
      storm("1.5")

      normal = quote(service_tier: :normal).amounts[:delivery_fee]
      premium = quote(service_tier: :premium).amounts[:delivery_fee]

      expect(premium).to eq((normal * BigDecimal("1.3")).round(2))
    end

    # THE CAP'S REAL JOB, and it is not the one it looks like. Capping only the
    # customer's total would leave the courier's uplift uncapped — a mistyped
    # 10 would pay him 10x base while the customer paid 2x, and the platform
    # would fund a gap no commission can cover. Clamping the SHORTAGE keeps
    # this true by construction.
    it "never pays the courier more than the customer pays, whatever is typed" do
      set("premium_price_multiplier", "1.3")
      set("max_total_multiplier", "2.0")
      storm("10")

      %i[normal premium].each do |tier|
        amounts = quote(service_tier: tier).amounts

        expect(amounts[:courier_fee]).to be <= amounts[:delivery_fee],
                                         "the courier out-earned the customer's fee on #{tier}"
      end
    end

    # A CEILING, asserted as a ceiling. The fee lands one minor unit under
    # `base x 2.0` rather than exactly on it, because the courier's share is
    # rounded to a payable amount before the tier multiplies it — the same
    # double-rounding `Monetary::ROUNDING_TOLERANCE` exists for. An exact
    # equality here would be asserting the arithmetic's residue rather than
    # the rule, and would go red the first time Hamma9900 retunes a tariff.
    it "holds the customer's total to the cap" do
      set("premium_price_multiplier", "1.3")
      set("max_total_multiplier", "2.0")
      base = quote.amounts[:delivery_fee]
      storm("10")
      ceiling = (base * BigDecimal("2.0")).round(2)

      capped = quote(service_tier: :premium).amounts[:delivery_fee]

      expect(capped).to be <= ceiling
      expect(capped).to be_within(Monetary::ROUNDING_TOLERANCE).of(ceiling)
    end

    # The audit half: a capped fare must be distinguishable from an uncapped
    # one, which is what the second column is for.
    it "records that it was capped, by disagreeing with itself" do
      set("max_total_multiplier", "2.0")
      storm("10")
      result = quote

      expect(result.shortage_multiplier).to eq(BigDecimal("2.0"))
      expect(result.shortage_multiplier_requested).to eq(BigDecimal("10"))
    end
  end

  # The merchant is not in this at all, and that is worth an example rather
  # than a comment: a shortage is about the ride, and touching `commission`
  # would move `merchant_payout` with it.
  it "leaves the merchant's side of the order completely alone" do
    calm = quote.amounts
    storm("1.8")
    wild = quote.amounts

    expect(wild[:items_total]).to eq(calm[:items_total])
    expect(wild[:commission]).to eq(calm[:commission])
    expect(wild[:merchant_payout]).to eq(calm[:merchant_payout])
  end
end
