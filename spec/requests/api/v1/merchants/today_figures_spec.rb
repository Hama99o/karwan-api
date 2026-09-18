require "rails_helper"

# ═══ WHAT A SHOP HAS TAKEN TODAY ═══════════════════════════════════════════
#
# PRODUCT.md:80 names exactly four numbers and forbids the rest: **"orders,
# items sold, cash received from riders, our commission. No charts."**
#
# ── AND "TODAY" HAD TO MEAN TODAY IN KABUL ───────────────────────────────
#
# `config.time_zone` was never set, so Rails ran in UTC and
# `Time.zone.now.beginning_of_day` was UTC midnight — **04:30 in Kabul**. Three
# figures were computed that way: this one, the courier's day, and the console's
# commission-today.
#
# The sharp end is a shop trading past midnight. An order at 01:00 Kabul fell
# into the PREVIOUS day's figures, so a restaurant's late trade belonged to
# yesterday while it was still being cooked — and the owner reconciling a cash
# drawer at closing would find the two disagreeing with no way to see why.
RSpec.describe "Api::V1::Merchants::Profile today", type: :request do
  def json
    JSON.parse(response.body)
  end

  let(:owner) { create(:user, :merchant_owner) }
  let!(:merchant) { create(:merchant, owner: owner, is_open: true) }
  let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(owner).last}" } }

  def today
    get "/api/v1/merchant/profile", headers: auth
    json.dig("profile", "today")
  end

  describe "the four numbers PRODUCT.md names" do
    before do
      order = create(:order, :delivered, merchant: merchant,
                                         items_total: 400, merchant_payout: 350, commission: 50)
      create(:order_item, order: order, quantity: 3, unit_price: 100, line_total: 300)
      create(:order, :ready, merchant: merchant)
    end

    it "counts every order today, and separately the delivered ones" do
      expect(today["orders"]).to eq(2)
      expect(today["delivered"]).to eq(1)
    end

    it "counts items sold, which is quantity and not lines" do
      expect(today["items_sold"]).to eq(3)
    end

    # What the shop was PAID, which under Model A is cash the rider handed over
    # at pickup — not the customer total, which is none of their business.
    it "shows what the shop received, grouped by currency and never summed across it" do
      expect(today["received"]).to eq({ "AFN" => "350.0" })
    end

    it "shows our commission, so the shop can check its own arithmetic" do
      expect(today["commission"]).to eq({ "AFN" => "50.0" })
    end

    # PRODUCT.md is explicit: "No charts." A merchant's screen is a workbench.
    it "carries nothing beyond the four and their breakdown" do
      expect(today.keys).to match_array(%w[orders delivered items_sold received commission])
    end
  end

  # ── THE DAY BOUNDARY, WHICH IS THE WHOLE REASON THIS SPEC EXISTS ─────────
  describe "the day it counts" do
    it "runs the app's clock on Kabul, not UTC" do
      expect(Time.zone.name).to eq("Kabul"),
                                "today would mean the UTC day — 04:30 to 04:30 in Kabul"
    end

    # ── WRITTEN IN ABSOLUTE UTC ON PURPOSE ────────────────────────────────
    #
    # The first version used `Time.zone.parse("2026-09-18 01:00")`, which moves
    # WITH the app's zone — so it passed under UTC too and the only thing
    # catching a reversion was the `Time.zone.name` assertion above. An example
    # that expresses its instants in the zone under test cannot detect a change
    # to that zone.
    #
    # These are fixed points on the clock. 21:30 UTC on the 17th is 02:00 Kabul
    # on the 18th; 00:30 UTC on the 18th is 05:00 Kabul the same morning. So the
    # shop is asking at five in the morning about trade it did at two.
    #
    #   Kabul: the day began 19:30 UTC on the 17th, so the order is in.
    #   UTC:   the day began 00:00 UTC on the 18th, so the order is OUT — the
    #          restaurant's late trade belonged to yesterday.
    it "counts trade done after midnight Kabul, asked about the same morning" do
      travel_to(Time.utc(2026, 9, 17, 21, 30)) do
        create(:order, :delivered, merchant: merchant, merchant_payout: 350, commission: 50)
      end

      travel_to(Time.utc(2026, 9, 18, 0, 30)) do
        expect(today["delivered"]).to eq(1),
                                     "02:00 Kabul trade fell outside the shop's own day — this is the UTC boundary"
        expect(today["received"]).to eq({ "AFN" => "350.0" })
      end
    end

    # And the other side: an order from before midnight must NOT be counted
    # once the day has turned, or "today" quietly means "the last 24 hours".
    it "does not count yesterday's late trade as today's" do
      travel_to(Time.zone.parse("2026-09-17 23:00")) do
        create(:order, :delivered, merchant: merchant, merchant_payout: 350, commission: 50)
      end

      travel_to(Time.zone.parse("2026-09-18 09:00")) do
        expect(today["delivered"]).to eq(0)
        expect(today["received"]).to eq({})
      end
    end
  end
end
