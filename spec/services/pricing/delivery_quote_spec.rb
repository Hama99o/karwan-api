require "rails_helper"

RSpec.describe Pricing::DeliveryQuote do
  let(:merchant) do
    create(:merchant, latitude: 34.5400, longitude: 69.1750,
                      commission_rate: 0.125, prep_time_minutes: 20)
  end

  def quote(items_total: 400, lat: 34.5658, lng: 69.2123)
    described_class.new(merchant: merchant, items_total: items_total,
                        delivery_latitude: lat, delivery_longitude: lng).call
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
end
