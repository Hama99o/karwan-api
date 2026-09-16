require "rails_helper"

# THE CUSTOMER'S CHOICE IS THE CONSENT TO BE BATCHED.
#
# `docs/SERVICE_TIERS_AND_BATCHING.md` §1 — the idea the whole feature turns
# on. Batching is not done to a customer behind their back; it is agreed in
# exchange for a lower price.
#
# The column ships before batching does, because **consent cannot be
# retrofitted**: nobody can ask a past customer whether their completed order
# could have been shared. A tier without batching costs nothing to honour — we
# simply never batch. Batching without a recorded tier is unshippable.
RSpec.describe "the service tier", type: :model do
  let(:merchant) { create(:merchant, latitude: 34.5553, longitude: 69.2075) }
  let(:category) { create(:catalog_category, merchant: merchant) }
  let!(:kabab) { create(:catalog_item, catalog_category: category, merchant: merchant, price: 400) }

  def place(tier)
    Orders::PlaceService.new(
      customer: create(:user, :customer), merchant: merchant,
      lines: [ { catalog_item_id: kabab.id, quantity: 1 } ],
      delivery_latitude: 34.5600, delivery_longitude: 69.2100,
      service_tier: tier
    ).call
  end

  describe "the default" do
    # Every row that existed before this column is `normal`, which is the
    # honest default: nothing has been batched and nobody was charged extra.
    it "is normal, on both demand types" do
      expect(create(:order).service_tier).to eq("normal")
      expect(create(:trip).service_tier).to eq("normal")
    end

    it "is what a customer gets if they say nothing" do
      expect(place(nil).service_tier).to eq("normal")
    end
  end

  describe "what it costs" do
    it "charges a premium delivery more than a normal one" do
      normal = place(:normal)
      premium = place(:premium)

      expect(premium.delivery_fee).to be > normal.delivery_fee
      expect(premium.customer_total).to be > normal.customer_total
    end

    it "charges exactly the configured multiple" do
      normal = place(:normal)
      premium = place(:premium)
      multiplier = Setting.fetch("premium_price_multiplier")

      expect(premium.delivery_fee).to eq((normal.delivery_fee * multiplier).round(2))
    end

    # The identity still closes — a premium order's parts sum to its whole.
    it "keeps the totals adding up" do
      premium = place(:premium)

      expect(premium.customer_total).to eq(premium.items_total + premium.delivery_fee)
      expect(premium).to be_valid
    end

    # THE UPLIFT IS THE PLATFORM'S ON A DELIVERY: what premium buys is the
    # capacity we hold empty, and the courier is paid for the run he did.
    it "does not raise what the courier is paid for the same run" do
      normal = place(:normal)
      premium = place(:premium)

      expect(premium.courier_fee).to eq(normal.courier_fee)
      expect(premium.delivery_fee - premium.courier_fee).to be > 0
    end

    it "leaves the merchant's side untouched, because premium is about carriage" do
      normal = place(:normal)
      premium = place(:premium)

      expect(premium.commission).to eq(normal.commission)
      expect(premium.merchant_payout).to eq(normal.merchant_payout)
    end
  end

  # ── THE SNAPSHOT RULE (docs/TESTING.md) ────────────────────────────────────
  #
  # A test that the tier is WRITTEN is not a test that it is FROZEN. Premium
  # bought this run outright, and that promise cannot be re-read from a live
  # setting later — so change the configuration underneath and assert nothing
  # on the placed order moves.
  describe "once it is placed" do
    it "keeps its tier when the configuration changes" do
      order = place(:premium)

      Setting.seed_defaults!
      Setting.find_by!(key: "premium_price_multiplier").update!(value: "9.0")

      expect(order.reload.service_tier).to eq("premium")
    end

    it "keeps its price when the multiplier changes" do
      order = place(:premium)
      frozen = order.customer_total

      Setting.seed_defaults!
      Setting.find_by!(key: "premium_price_multiplier").update!(value: "9.0")

      expect(order.reload.customer_total).to eq(frozen)
      expect(order.reload.delivery_fee).to eq(frozen - order.items_total)
    end

    # And the promise itself does not move: raising the batch ceiling must not
    # make a premium order combinable retrospectively.
    it "stays uncombinable when batching is switched on" do
      order = place(:premium)

      Setting.seed_defaults!
      Setting.find_by!(key: "batch_max_jobs").update!(value: "3")

      expect(ServiceTiers.batchable?(order.reload.service_tier)).to be false
    end
  end

  describe "what the tier means" do
    it "lets a normal job share a run and never a premium one" do
      expect(ServiceTiers.batchable?("normal")).to be true
      expect(ServiceTiers.batchable?("premium")).to be false
    end

    # v0 honours every tier by never batching at all, which is why the ceiling
    # starts at one.
    it "ships with batching off, so the promise is trivially kept" do
      expect(Setting.fetch("batch_max_jobs")).to eq(1)
    end
  end

  describe "what the courier sees before accepting" do
    it "puts the tier and its plain consequence on the offer card" do
      order = place(:premium)
      courier = create(:user, :courier)
      offer = create(:offer, courier: courier, offerable: order)

      card = Couriers::JobSerializer.render_as_hash(
        order, view: :offer, offer: offer, from: [ 34.5553, 69.2075 ]
      )

      expect(card[:service_tier]).to eq("premium")
      expect(card[:can_be_combined]).to be false
    end

    it "says a normal job may be combined" do
      order = place(:normal)
      courier = create(:user, :courier)
      offer = create(:offer, courier: courier, offerable: order)

      card = Couriers::JobSerializer.render_as_hash(
        order, view: :offer, offer: offer, from: [ 34.5553, 69.2075 ]
      )

      expect(card[:can_be_combined]).to be true
    end
  end
end
