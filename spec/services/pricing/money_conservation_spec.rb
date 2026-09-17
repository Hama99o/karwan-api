require "rails_helper"

# ═══ MONEY IS CONSERVED, AND EVERY PARTY GETS WHAT THE MODEL SAYS ═══════════
#
# Four knobs now move money on a single delivery — the premium tier multiplier,
# the shortage multiplier, the cap on their product, and the distance top-up —
# and they compose. Each was tested against its own intent; none of them was
# tested against *everyone else's share at the same time*.
#
# The commission → `merchant_payout` leak was found by reasoning about it. That
# works while somebody is looking. **This is the gate that works when nobody
# is**, because it does not know about any particular knob: it asserts the
# accounting identity over a matrix, so any future change that quietly moves
# money from one party to another fails it without anyone having thought of
# that path.
#
# ── THE IDENTITY, FOR A DELIVERY ──────────────────────────────────────────
#
# One cash journey, Model A. The customer pays once, at the door, in cash:
#
#     customer_total  =  merchant keeps  +  courier keeps  +  platform keeps
#
# with each share built from INDEPENDENT stored fields — see `intended` below:
#
#   merchant keeps   `merchant_payout` — handed over at the counter
#   courier keeps    `courier_fee`, plus any `commission_topup`
#   platform keeps   `commission - commission_topup`, plus the delivery margin
#                    `delivery_fee - courier_fee`
#
# **CONSERVATION IS NOT ATTRIBUTION**, and the two are asserted separately on
# purpose. Money cannot vanish — the customer's cash goes *somewhere* — so a
# conservation check built from the residual would be satisfied by a model that
# pays entirely the wrong party. Attribution is the half that says the right
# party got it, and it is the half that is currently broken.
RSpec.describe "money conservation" do
  let(:merchant) do
    create(:merchant, latitude: 34.5553, longitude: 69.2075, commission_rate: 0.125)
  end

  def set(key, value)
    Setting.find_or_initialize_by(key: key)
           .update!(value: value.to_s, value_type: Setting::DEFINITIONS.fetch(key)[:type])
  end

  def quote(tier:, items_total:, lat:, lng:)
    Pricing::DeliveryQuote.new(merchant: merchant, items_total: items_total,
                               delivery_latitude: lat, delivery_longitude: lng,
                               service_tier: tier).call.amounts
  end

  # ── TWO WAYS OF ASKING, AND THE DIFFERENCE IS THE POINT ──────────────────
  #
  # **INTENDED** — what each party should end with, built from the stored
  # fields the model says describe their shares. Every term is independent, so
  # the sum is a real constraint: change any one field and the identity breaks.
  #
  # **ACTUAL** — what each party is physically left holding once the cash has
  # moved: the courier collects the total, hands over the payout, and his
  # wallet is charged the commission less anything credited back.
  #
  # The courier's ACTUAL position is a RESIDUAL — it is whatever is left in his
  # hand — so `actual` sums to `customer_total` by arithmetic and asserting it
  # would prove nothing. **The first version of this file did exactly that and
  # could not have failed.** `intended` is the one worth asserting, and
  # comparing the two is what finds a party being paid the wrong amount.
  def intended(amounts, topup: 0)
    topup = BigDecimal(topup.to_s)

    {
      merchant: amounts[:merchant_payout],
      courier: amounts[:courier_fee] + topup,
      platform: (amounts[:commission] - topup) +
                (amounts[:delivery_fee] - amounts[:courier_fee])
    }
  end

  def actual(amounts, topup: 0)
    topup = BigDecimal(topup.to_s)

    {
      merchant: amounts[:merchant_payout],
      courier: amounts[:customer_total] - amounts[:merchant_payout] -
               (amounts[:commission] - topup),
      platform: amounts[:commission] - topup
    }
  end

  # normal/premium x shortage off/on/capped x near/far x ordinary/zero
  # commission. Property over a matrix rather than one example per case: the
  # point is that no COMBINATION leaks, and combinations are where they hide.
  TIERS = %i[normal premium].freeze
  STORMS = {
    "no storm" => nil,
    "a storm" => "1.5",
    "a mistyped storm the cap clamps" => "10"
  }.freeze
  DISTANCES = {
    "a short hop" => [ 34.5560, 69.2080 ],
    "a long delivery" => [ 34.6200, 69.3000 ]
  }.freeze
  BASKETS = { "an ordinary basket" => 400, "a tiny basket" => 20 }.freeze

  TIERS.each do |tier|
    STORMS.each do |storm_name, storm|
      DISTANCES.each do |distance_name, (lat, lng)|
        BASKETS.each do |basket_name, items_total|
          context "#{tier}, #{storm_name}, #{distance_name}, #{basket_name}" do
            before do
              set("max_total_multiplier", "2.0")
              next if storm.nil?

              set("shortage_multiplier_enabled", "true")
              set("shortage_multiplier", storm)
            end

            let(:amounts) { quote(tier: tier, items_total: items_total, lat: lat, lng: lng) }

            it "conserves every afghani the customer pays" do
              expect(intended(amounts).values.sum).to eq(amounts[:customer_total])
            end

            it "conserves it with a top-up moving between two of the shares" do
              expect(intended(amounts, topup: amounts[:commission]).values.sum)
                .to eq(amounts[:customer_total])
            end

            it "leaves nobody holding a negative amount" do
              intended(amounts).each do |party, amount|
                expect(amount).to be >= 0, "#{party} ends up owing money"
              end
            end

            # The customer's total is the only figure they ever see, and it is
            # frozen. It must be the sum of the two things they were shown.
            it "charges the customer exactly the basket plus the fee" do
              expect(amounts[:customer_total])
                .to eq(amounts[:items_total] + amounts[:delivery_fee])
            end

            # A top-up moves money from the platform to the courier and must
            # not create or destroy any: the customer pays the same, the
            # merchant receives the same.
            it "moves the top-up from our share to his, and nothing else" do
              without = intended(amounts)
              with = intended(amounts, topup: amounts[:commission])

              expect(with[:merchant]).to eq(without[:merchant])
              expect(with[:courier] + with[:platform]).to eq(without[:courier] + without[:platform])
              expect(with[:courier]).to be > without[:courier]
            end
          end
        end
      end
    end
  end

  # ═══ ATTRIBUTION — WHO SHOULD GET IT, AS THE MODEL DESCRIBES ITSELF ═══════
  #
  # `Pricing::DeliveryQuote`, in capitals: *"THE PREMIUM UPLIFT IS THE
  # PLATFORM'S, on a delivery. What premium buys is the capacity we hold empty
  # for it, and the courier is paid for the run he did."* `Order` says the same
  # from the other side: *"The platform's delivery margin is `delivery_fee -
  # courier_fee`."*
  #
  # So the platform's share should be that margin plus the commission, less
  # anything given back.
  describe "the platform receives what the model says it does" do
    let(:amounts) { quote(tier: tier, items_total: 400, lat: 34.5658, lng: 69.2123) }

    def platform_should_get(amounts)
      intended(amounts)[:platform]
    end

    context "on a normal order" do
      let(:tier) { :normal }

      it "collects the commission, and there is no delivery margin to collect" do
        expect(actual(amounts)[:platform]).to eq(platform_should_get(amounts))
      end

      it "hands the courier exactly what the model says he earns" do
        expect(actual(amounts)[:courier]).to eq(intended(amounts)[:courier])
      end
    end

    # ── THE LEAK THIS FILE WAS WRITTEN TO FIND ─────────────────────────────
    #
    # On a 400 AFN order the customer pays 24 AFN more for premium and **the
    # courier ends up holding all 24 of it**. The platform receives exactly the
    # 50 it receives on a normal order.
    #
    # The cash mechanics are the whole reason: the courier collects
    # `customer_total`, hands over `merchant_payout`, and his wallet is charged
    # `commission`. Nothing anywhere charges him `delivery_fee - courier_fee` —
    # `Couriers::CashPosition` sums `commission` alone, and
    # `Order#platform_cash_held` returns `commission` alone. So the uplift is
    # charged to the customer and never collected from anybody.
    #
    # PENDING RATHER THAN REWRITTEN TO MATCH THE CODE, deliberately: fixing it
    # means deciding whether the courier owes the premium margin, which is a
    # money rule and therefore Hamma9900's (HOW_WE_WORK, decision rights). This
    # example goes GREEN the day it is fixed and fails loudly if somebody
    # "fixes" it by changing the expectation.
    context "on a premium order" do
      let(:tier) { :premium }

      it "collects the premium uplift it charged the customer for" do
        pending "OPEN: the premium uplift is charged and never collected — Hamma9900's call"

        expect(actual(amounts)[:platform]).to eq(platform_should_get(amounts))
      end

      # What IS true today, asserted so the leak cannot grow silently while the
      # question is open: the customer pays more and the courier keeps it.
      it "currently hands the whole uplift to the courier" do
        share = actual(amounts)
        uplift = amounts[:delivery_fee] - amounts[:courier_fee]

        expect(uplift).to be > 0
        expect(share[:platform]).to eq(amounts[:commission])
        expect(share[:courier]).to eq(amounts[:courier_fee] + uplift)
      end
    end
  end

  # ═══ WHERE PLATFORM REVENUE IS COLLECTED — THE ONE OPEN QUESTION ═════════
  #
  # In a cash model the platform never touches the money, so every afghani of
  # our revenue travels back through some channel — and there must be exactly
  # ONE. MONEY_AND_SETTLEMENT.md §2 says that channel is the RESTAURANT: the
  # courier hands over the food PLUS our margin (315 on a 300 meal) and the
  # restaurant deposits weekly. The code says it is the COURIER'S WALLET: he
  # hands over the food MINUS our commission (250) and his wallet is charged.
  #
  # The difference is exactly the platform's whole revenue on the order. These
  # are two collection mechanisms, not two spellings of one.
  #
  # PENDING, NAMING HIM, for the same reason as the premium leak below: which
  # channel collects our money is a money rule and therefore Hamma9900's. The
  # pair is deliberate — the pending goes GREEN when it is implemented and the
  # companion pin goes RED, so one sentence from him produces a worklist.
  describe "the channel platform revenue arrives through" do
    let(:amounts) { quote(tier: :normal, items_total: 400, lat: 34.5658, lng: 69.2123) }

    it "hands the merchant the food PLUS our margin, as §2 describes" do
      pending "OPEN: §2 says the restaurant collects for us; the code charges the wallet"

      expect(amounts[:merchant_payout])
        .to eq(amounts[:items_total] + (amounts[:delivery_fee] - amounts[:courier_fee]))
    end

    it "currently hands the merchant the food LESS our commission" do
      expect(amounts[:merchant_payout]).to eq(amounts[:items_total] - amounts[:commission])
    end
  end

  # ═══ A RIDE — THE SIMPLER HALF, AND IT BALANCES ══════════════════════════
  #
  # No merchant and no advance: the passenger pays the fare, the courier keeps
  # his earnings, the platform takes its commission from the same wallet.
  # `Trip` validates `fare == commission + courier_earnings`, so this is that
  # identity asserted from the OUTSIDE — through the quote, not the validation.
  describe "a ride" do
    %i[normal premium].each do |tier|
      it "splits the fare between the courier and us, with nothing left over (#{tier})" do
        fare = Pricing::RideQuote.new(
          pickup_latitude: 34.5553, pickup_longitude: 69.2075,
          dropoff_latitude: 34.5658, dropoff_longitude: 69.2123,
          service_tier: tier
        ).call.amounts

        expect(fare[:courier_earnings] + fare[:commission]).to eq(fare[:fare])
      end
    end
  end
end
