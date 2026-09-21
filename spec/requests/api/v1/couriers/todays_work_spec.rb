require "rails_helper"

# ═══ PRODUCT.md'S RIDER "TODAY", WHICH NOTHING SERVED ══════════════════════
#
# "**Today** — deliveries, earnings, cash currently in hand." Every other Rider
# screen had an endpoint; this had none, so a courier ending a shift could not
# answer what he had earned without adding up wallet entries himself.
RSpec.describe "Api::V1::Couriers::Today", type: :request do
  def json
    JSON.parse(response.body)
  end

  let(:courier) { create(:user, :courier) }
  let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(courier).last}" } }

  def delivered(fee:, at: Time.current)
    create(:order, :with_items, :delivered, courier: courier, courier_fee: fee,
                                            items_total: 400, commission: 50, merchant_payout: 350,
                                            delivery_fee: fee, customer_total: 400 + fee,
                                            delivered_at: at)
  end

  def completed_ride(earnings:, at: Time.current)
    create(:trip, :completed, courier: courier, fare: earnings + 20,
                              commission: 20, courier_earnings: earnings, completed_at: at)
  end

  # ── BOTH DEMAND TYPES, NAMED SEPARATELY ──────────────────────────────────
  #
  # PRODUCT.md says "deliveries" because it was written when this was food-only.
  # Correction 9: one person, two job kinds, and the shared pool is the business
  # thesis. Collapsing them would hide the half CLAUDE.md says the company turns
  # on.
  it "counts a courier's deliveries and rides separately" do
    2.times { delivered(fee: 100) }
    completed_ride(earnings: 150)

    get "/api/v1/courier/today", headers: auth

    expect(response).to have_http_status(:ok)
    expect(json["deliveries"]).to eq(2)
    expect(json["rides"]).to eq(1), "the ride half of the pool is invisible"
  end

  it "adds up what he earned from both, by currency" do
    2.times { delivered(fee: 100) }
    completed_ride(earnings: 150)

    get "/api/v1/courier/today", headers: auth

    money = json["earnings"].first
    expect(money["currency"]).to eq("AFN")
    expect(money["deliveries"].to_f).to eq(200)
    expect(money["rides"].to_f).to eq(150)
    expect(money["total"].to_f).to eq(350)
  end

  # ── CASH IN HAND IS NOT A TODAY FIGURE ───────────────────────────────────
  #
  # It is a running total and can include money collected yesterday and not yet
  # settled. Under a heading saying "today" it would read as "this is what I
  # took today", and a courier reconciling his pocket would come up short by
  # exactly what he owes from yesterday. Hence the name.
  it "names cash in hand as a running total, not a daily one" do
    get "/api/v1/courier/today", headers: auth

    expect(json).to have_key("cash_in_hand_now")
    expect(json).not_to have_key("cash_in_hand"),
                        "an unqualified name here reads as money collected today"
    expect(json).to have_key("cash_allowance_remaining")
  end

  # THE SAME SOURCE as the shift screen and the wallet screen, so three screens
  # cannot disagree about what he is holding.
  it "reports the same cash figure the shift screen reports" do
    delivered(fee: 100)

    get "/api/v1/courier/today", headers: auth
    from_today = json["cash_in_hand_now"]

    get "/api/v1/courier/shift", headers: auth
    from_shift = json["cash_in_hand"]

    expect(from_today[Monetary::DEFAULT_CURRENCY].to_f).to eq(from_shift.to_f),
                                                          "two screens disagree about the cash in his pocket"
  end

  it "leaves yesterday's work out" do
    delivered(fee: 100, at: 1.day.ago)
    completed_ride(earnings: 150, at: 1.day.ago)

    get "/api/v1/courier/today", headers: auth

    expect(json["deliveries"]).to eq(0)
    expect(json["rides"]).to eq(0)
    expect(json["earnings"]).to be_empty
  end

  # A job in flight is not earnings. He is paid for work he finished.
  it "does not count a job he is still carrying" do
    create(:order, :with_items, :picked_up, courier: courier, courier_fee: 100)

    get "/api/v1/courier/today", headers: auth

    expect(json["deliveries"]).to eq(0)
    expect(json["earnings"]).to be_empty
  end

  # ── THE STATUS IS FILTERED, NOT JUST THE TIMESTAMP ───────────────────────
  #
  # Dropping `status: :delivered` and keeping only `delivered_at` left every
  # other example green, because nothing built through the app has one without
  # the other — `delivered` is terminal, so no transition leaves it. The guard
  # is for a row that arrived ANOTHER way: a migration, a console fix, a seed
  # that writes columns directly. `db/seeds/stress.rb` writes exactly that shape
  # of row in bulk.
  #
  # Planted with `update_columns` to bypass the state machine, which is the only
  # way to supply the input the two versions differ on. Same reasoning as the
  # merchant screen's summed payout: a check nothing can currently trip is still
  # the check that catches the day something does.
  it "does not count a row whose timestamp says delivered and whose status does not" do
    order = delivered(fee: 100)
    order.update_columns(status: Order.statuses[:failed], failed_at: Time.current)

    get "/api/v1/courier/today", headers: auth

    expect(order.reload.delivered_at).to be_present, "the row must keep the timestamp, or this proves nothing"
    expect(json["deliveries"]).to eq(0),
                                 "counted on the timestamp alone, so a row the status contradicts is paid for"
    expect(json["earnings"]).to be_empty
  end

  it "never shows another courier's day" do
    other = create(:user, :courier)
    create(:order, :with_items, :delivered, courier: other, courier_fee: 999,
                                            items_total: 400, commission: 50, merchant_payout: 350,
                                            delivery_fee: 999, customer_total: 1399,
                                            delivered_at: Time.current)
    delivered(fee: 100)

    get "/api/v1/courier/today", headers: auth

    expect(json["deliveries"]).to eq(1)
    expect(json["earnings"].first["total"].to_f).to eq(100)
  end
end
