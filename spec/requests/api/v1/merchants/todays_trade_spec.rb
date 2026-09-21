require "rails_helper"

# ═══ PRODUCT.md'S FIFTH RESTAURANT SCREEN, WHICH NOTHING SERVED ════════════
#
# "**Today** — orders, items sold, cash received from riders, our commission.
# No charts." Four of the five Restaurant screens had endpoints; this one had
# none.
#
# ── THE CONSTRAINT THAT SHAPES EVERY EXAMPLE BELOW ────────────────────────
#
# It must be the SAME ARITHMETIC as `Merchants::IssueStatement`, over a day
# instead of a week. A shop that reads one number here on Friday and a different
# one on the statement for the same week stops believing both — and the
# statement is the one that matters, because it is the financial record already
# shown to a partner.
RSpec.describe "Api::V1::Merchants::Today", type: :request do
  def json
    JSON.parse(response.body)
  end

  let(:owner) { create(:user, :merchant_owner) }
  let(:merchant) { create(:merchant, owner: owner) }
  let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(owner).last}" } }

  # Money the shop KEPT: delivered, with its own columns rather than a residual.
  def delivered_order(items_total:, commission:, at: Time.current, quantity: 1)
    order = create(:order, :delivered, merchant: merchant,
                                       items_total: items_total, commission: commission,
                                       merchant_payout: items_total - commission,
                                       delivery_fee: 100,
                                       customer_total: items_total + 100,
                                       courier_fee: 100,
                                       delivered_at: at)
    # `OrderItem` enforces `line_total == (unit_price + options_total) * quantity`
    # — a row the app could not produce is a fixture that proves nothing, which
    # is `docs/TESTING.md`'s fourth question. So the unit price is derived from
    # the line, not stated beside it.
    create(:order_item, order: order, name: "Kabab",
                        unit_price: (items_total / quantity.to_d), options_total: 0,
                        line_total: items_total, quantity: quantity)
    order
  end

  it "reports the four figures PRODUCT.md names" do
    delivered_order(items_total: 400, commission: 50, quantity: 2)
    delivered_order(items_total: 300, commission: 40, quantity: 1)

    get "/api/v1/merchant/today", headers: auth

    expect(response).to have_http_status(:ok)
    day = json["by_currency"].first
    expect(day["orders"]).to eq(2)
    expect(day["items_sold"]).to eq(3), "items sold counts FOOD, not orders — three kebabs is three"
    expect(day["items_total"].to_f).to eq(700)
    expect(day["commission"].to_f).to eq(90)
    expect(day["net_received"].to_f).to eq(610)
    expect(day["currency"]).to eq("AFN")
  end

  # ── THE WHOLE POINT: IT MUST AGREE WITH THE STATEMENT ────────────────────
  #
  # Run against the real `IssueStatement` over a period containing only today,
  # rather than reasoned about. If these two ever diverge, a shop is told two
  # different things about one day's trade.
  it "gives the same figures as the weekly statement for the same orders" do
    delivered_order(items_total: 400, commission: 50, quantity: 2)
    delivered_order(items_total: 300, commission: 40, quantity: 1)

    get "/api/v1/merchant/today", headers: auth
    today = json["by_currency"].first

    statement = Merchants::IssueStatement.new(merchant, period_start: Date.current,
                                                        period_end: Date.current).call.first

    expect(statement.orders_count).to eq(today["orders"])
    expect(statement.items_total.to_f).to eq(today["items_total"].to_f)
    expect(statement.commission.to_f).to eq(today["commission"].to_f)
    expect(statement.net_received.to_f).to eq(today["net_received"].to_f),
                                            "the daily screen and the weekly statement disagree about one day"
  end

  # ── net_received IS SUMMED, NEVER DERIVED ────────────────────────────────
  #
  # `IssueStatement` says why: *"a residual agrees with itself by construction
  # and could never disagree with the orders it describes, which is the one
  # thing a statement exists to let somebody check."*
  #
  # THIS EXAMPLE HAD TO BE WRITTEN TWICE. Planting `items_total - commission` in
  # place of the summed payout left every other example green, because `Order`
  # VALIDATES `merchant_payout == items_total - commission`, so nothing built
  # through the app can tell the two apart. That validation is exactly why the
  # residual looks harmless — and exactly why summing matters: the check exists
  # for a row that got in another way.
  #
  # So this plants that row with `update_columns`, deliberately bypassing the
  # validation. `docs/TESTING.md` asks whether a database state could occur
  # through the app; here the answer is no, and that is the point — a migration,
  # a console fix or a future bug is what this must be able to show.
  it "reports the payout that is stored, not the one it could have calculated" do
    order = delivered_order(items_total: 400, commission: 50)
    expect(order.merchant_payout.to_f).to eq(350), "the fixture must start consistent, or this proves nothing"

    order.update_columns(merchant_payout: 300)

    get "/api/v1/merchant/today", headers: auth

    day = json["by_currency"].first
    expect(day["net_received"].to_f).to eq(300),
                                        "the screen recomputed the payout instead of reading it, so a row whose " \
                                        "columns disagree would be reported as if it agreed"
    expect(day["items_total"].to_f).to eq(400)
    expect(day["commission"].to_f).to eq(50)
  end

  # Under Model A the courier pays at PICKUP, so "cash received" looks like it
  # should be `merchant_paid_at`. §5 is why it is not: when food comes back
  # "the restaurant refunds him his advance and pays his fee", so a picked-up
  # order is money the shop may have to hand straight back.
  it "does not count an order that is still out on the road" do
    delivered_order(items_total: 400, commission: 50)
    create(:order, :picked_up, merchant: merchant, items_total: 999, commission: 99,
                               merchant_payout: 900, delivery_fee: 100,
                               customer_total: 1099, courier_fee: 100)

    get "/api/v1/merchant/today", headers: auth

    expect(json["by_currency"].first["items_total"].to_f).to eq(400),
                                                            "a picked-up order is counted as money kept"
    expect(json["in_the_kitchen"]).to eq(1), "the shop cannot see what it is still waiting for"
  end

  it "leaves yesterday out" do
    delivered_order(items_total: 400, commission: 50, at: 1.day.ago)

    get "/api/v1/merchant/today", headers: auth

    expect(json["by_currency"]).to be_empty
  end

  # A rejected order is not outstanding work — `live` excludes every terminal
  # state, so the kitchen count must not include it.
  it "does not count a rejected order as still in the kitchen" do
    create(:order, merchant: merchant).update!(status: :rejected, rejected_at: Time.current)

    get "/api/v1/merchant/today", headers: auth

    expect(json["in_the_kitchen"]).to eq(0)
  end

  # One shop's trade is never another's. The scope is derived from ownership,
  # never from a parameter.
  it "never shows another shop's day" do
    other = create(:merchant)
    create(:order, :delivered, merchant: other, items_total: 5000, commission: 500,
                               merchant_payout: 4500, delivery_fee: 100,
                               customer_total: 5100, courier_fee: 100, delivered_at: Time.current)
    delivered_order(items_total: 400, commission: 50)

    get "/api/v1/merchant/today", headers: auth

    expect(json["by_currency"].first["items_total"].to_f).to eq(400)
  end

  it "refuses a caller who is not a merchant owner" do
    customer = create(:user, :customer)

    get "/api/v1/merchant/today", headers: { "Authorization" => "Bearer #{UserSession.issue!(customer).last}" }

    expect(response).to have_http_status(:forbidden).or have_http_status(:unauthorized)
  end
end
