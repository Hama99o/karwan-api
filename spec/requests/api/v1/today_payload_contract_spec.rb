require "rails_helper"

# ═══ THE TWO "TODAY" SHAPES, COMMITTED SO A CLIENT CAN BUILD AGAINST THEM ══
#
# `settlements_payload_contract_spec.rb` states the reasoning and this follows
# it: *"The mobile session declined to write a settlements parser because the
# payload had never been SEEN — only described. A description is an intention; a
# response is a fact, and the two drift silently."*
#
# Both endpoints are new, neither has a client, and `docs/NOTES.md` describes
# them in prose. These commit the fact.
#
# ── WHAT THE FIXTURES PROTECT, IN THE CLIENT'S TERMS ──────────────────────
#
#   · **Money is a STRING, counts are NUMBERS.** `"700.0"` beside `orders: 2`.
#     A client doing arithmetic on the first without parsing gets string
#     concatenation, and `>` on it compares lexically — which is wrong for
#     negatives, the trap the settlements fixture exists for.
#   · **Per-currency money is always an ARRAY of `{currency, …}`**, never a map
#     keyed by currency. The first capture of `courier/today` had `earnings` as
#     an array and `cash_in_hand_now` as a map — two shapes for one idea in one
#     payload. Capturing it is what found that; describing it had not.
#   · **`cash_allowance_remaining` is the documented exception and a scalar**,
#     because `cash_in_hand_limit` is an AFN-denominated `Setting` and
#     `CashPosition#remaining_allowance` says the comparison is AFN-only. A
#     per-currency array there would imply a per-currency limit that does not
#     exist.
#   · **`from`/`to` are KABUL boundaries** (+04:30), not the server's day. A
#     client comparing them against a UTC day is off by four and a half hours
#     and will attribute the dinner rush to the wrong date.
#   · **An empty day is `[]`, not absent** — the client renders zero, not a
#     spinner.
RSpec.describe "the today payloads", type: :request do
  def fixture(name)
    JSON.parse(Rails.root.join("spec/fixtures/files/#{name}.json").read)
  end

  # Fixed instant, because the whole payload is a day boundary. A live clock
  # would make this fail at midnight Kabul and pass every other hour, which is
  # the flake shape `otp_verification_spec` already paid for.
  let(:noon_in_kabul) { Time.zone.parse("2026-09-22 14:00:00 +0430") }

  describe "GET /api/v1/merchant/today" do
    let(:owner) { create(:user, :merchant_owner) }
    let(:merchant) { create(:merchant, owner: owner) }
    let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(owner).last}" } }

    it "matches the committed fixture exactly, field for field" do
      travel_to noon_in_kabul do
        [ [ 400, 50, 2 ], [ 300, 40, 1 ] ].each do |items_total, commission, qty|
          order = create(:order, :delivered, merchant: merchant, items_total: items_total,
                                             commission: commission, merchant_payout: items_total - commission,
                                             delivery_fee: 100, customer_total: items_total + 100,
                                             courier_fee: 100, delivered_at: Time.current)
          create(:order_item, order: order, name: "کباب", unit_price: (items_total / qty.to_d),
                              options_total: 0, line_total: items_total, quantity: qty)
        end
        create(:order, :preparing, merchant: merchant)

        get "/api/v1/merchant/today", headers: auth

        expect(JSON.parse(response.body)).to eq(fixture("merchant_today")),
                                             "the merchant today payload changed. If deliberate, regenerate " \
                                             "spec/fixtures/files/merchant_today.json and tell the mobile session."
      end
    end

    # The state a screen meets first and most often, and the one a description
    # never covers.
    it "sends an empty array rather than omitting the day" do
      travel_to noon_in_kabul do
        # `merchant` is referenced deliberately: it is a lazy `let`, and without
        # touching it there is no shop, `require_merchant!` refuses, and the
        # example asserts against an ERROR body while looking like it asserts
        # against an empty day.
        expect(merchant).to be_present

        get "/api/v1/merchant/today", headers: auth

        expect(response).to have_http_status(:ok), "not the payload at all: #{response.body[0, 120]}"

        body = JSON.parse(response.body)
        expect(body["by_currency"]).to eq([])
        expect(body).to have_key("in_the_kitchen")
        expect(body["from"]).to end_with("+04:30"), "the day boundary is not Kabul's"
      end
    end
  end

  describe "GET /api/v1/courier/today" do
    let(:courier) { create(:user, :courier) }
    let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(courier).last}" } }

    it "matches the committed fixture exactly, field for field" do
      travel_to noon_in_kabul do
        2.times do
          create(:order, :with_items, :delivered, courier: courier, courier_fee: 100,
                                                  items_total: 400, commission: 50, merchant_payout: 350,
                                                  delivery_fee: 100, customer_total: 500,
                                                  delivered_at: Time.current, payment_status: :collected)
        end
        create(:trip, :completed, courier: courier, fare: 170, commission: 20,
                                  courier_earnings: 150, completed_at: Time.current)

        get "/api/v1/courier/today", headers: auth

        expect(JSON.parse(response.body)).to eq(fixture("courier_today")),
                                             "the courier today payload changed. If deliberate, regenerate " \
                                             "spec/fixtures/files/courier_today.json and tell the mobile session."
      end
    end

    # ── ONE PARSER PER PAYLOAD ───────────────────────────────────────────
    #
    # Both per-currency lists are arrays of objects carrying their own
    # `currency`. This is the assertion that stops the map creeping back.
    it "uses one shape for every per-currency figure" do
      travel_to noon_in_kabul do
        create(:order, :with_items, :delivered, courier: courier, courier_fee: 100,
                                                items_total: 400, commission: 50, merchant_payout: 350,
                                                delivery_fee: 100, customer_total: 500,
                                                delivered_at: Time.current, payment_status: :collected)

        get "/api/v1/courier/today", headers: auth
        body = JSON.parse(response.body)

        [ body["earnings"], body["cash_in_hand_now"] ].each do |list|
          expect(list).to be_an(Array), "a per-currency figure is not an array — one payload, two parsers"
          list.each { |row| expect(row).to have_key("currency") }
        end
        expect(body["cash_allowance_remaining"]).to be_a(String),
                                                    "the allowance is AFN-only by the limit's own denomination"
      end
    end

    it "sends empty arrays on a day with no work" do
      travel_to noon_in_kabul do
        get "/api/v1/courier/today", headers: auth

        body = JSON.parse(response.body)
        expect(body["deliveries"]).to eq(0)
        expect(body["rides"]).to eq(0)
        expect(body["earnings"]).to eq([])
      end
    end
  end

  # Money as a string is the single most expensive thing to get wrong on the
  # client, and it is invisible in a description.
  it "sends money as strings and counts as numbers" do
    merchant = fixture("merchant_today")["by_currency"].first
    courier = fixture("courier_today")

    expect(merchant["items_total"]).to be_a(String)
    expect(merchant["orders"]).to be_an(Integer)
    expect(courier["earnings"].first["total"]).to be_a(String)
    expect(courier["deliveries"]).to be_an(Integer)
  end
end
