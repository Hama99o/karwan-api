require "rails_helper"

# ── THE WEEK A SHOP ADVERTISES ─────────────────────────────────────────────
#
# These rows existed, the customer's card read them, and the shop could neither
# see nor change them — every correction went through an operator.
# `Merchant#hours_known?` and `#next_opens_at` are computed from this table, so
# the line a customer reads about when a shop opens was maintained by somebody
# who is not the shop.
RSpec.describe "A merchant sets its own opening hours", type: :request do
  def json = JSON.parse(response.body)

  let(:owner) { create(:user, :merchant_owner) }
  let(:merchant) { create(:merchant, owner: owner) }
  let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(owner).last}" } }

  before { merchant.opening_hours.destroy_all }

  def put_week(rows)
    put "/api/v1/merchant/opening_hours", params: { opening_hours: rows }, headers: auth, as: :json
  end

  # ── A ROUND TRIP DOES NOT DISCRIMINATE, AND THIS ONE DOES NOT CLAIM TO ───
  #
  # This example was first written as "the round trip proves the timezone trap
  # is fixed". It does not. **Planted the trap — `:time` back in
  # `time_zone_aware_types` — and this example stayed green**, because a write
  # and a read through the SAME conversion cancel out. The documented bug was a
  # row written outside that path and read through it.
  #
  # Kept, because the round trip is still the contract a client depends on, and
  # the example BELOW is the one that discriminates.
  it "gives back the same clock face it was given" do
    put_week([ { day_of_week: 1, opens_at: "09:00", closes_at: "17:00" } ])

    expect(response).to have_http_status(:ok)
    expect(json["opening_hours"].first).to include("opens_at" => "09:00", "closes_at" => "17:00")

    get "/api/v1/merchant/opening_hours", headers: auth
    expect(json["opening_hours"].first).to include("opens_at" => "09:00", "closes_at" => "17:00"),
                                           "the wall clock moved between write and read"
  end

  # ── THE ASSERTION THAT ACTUALLY DISCRIMINATES ────────────────────────────
  #
  # `opens_at` is a `t.time` column. Rails puts `:time` in
  # `time_zone_aware_types`, which is right for an instant and wrong for a wall
  # clock: with it on, a row stored as 09:00 reads back as 13:30 and a shop is
  # advertised as opening four and a half hours late.
  #
  # Only the STORED value tells the two apart — it is what a SQL report, a raw
  # console query or a second service would read. Same technique as
  # `spec/requests/admin/opening_hours_can_be_set_spec.rb`, applied to the
  # merchant's own write path, because the console and the shop reach the same
  # column by different routes.
  it "stores what the shop typed, as a wall clock, not shifted into UTC" do
    put_week([ { day_of_week: 1, opens_at: "09:00", closes_at: "17:00" } ])

    row = MerchantOpeningHour.connection.select_one(
      "SELECT opens_at, closes_at FROM merchant_opening_hours WHERE merchant_id = #{merchant.id}"
    )

    expect(row["opens_at"].to_s).to start_with("09:00"),
                                    "the database holds #{row['opens_at']} for a 09:00 opening — `:time` is " \
                                    "being treated as an instant rather than a wall clock"
    expect(row["closes_at"].to_s).to start_with("17:00")
  end

  # A shop that shuts for the afternoon and reopens is ordinary. The schema's
  # merchant_id/day_of_week index is deliberately not unique.
  it "keeps two windows on one day" do
    put_week([
      { day_of_week: 2, opens_at: "08:00", closes_at: "12:00" },
      { day_of_week: 2, opens_at: "16:00", closes_at: "22:00" }
    ])

    windows = json["opening_hours"].select { |h| h["day_of_week"] == 2 }
    expect(windows.size).to eq(2), "the afternoon closure was collapsed into one window"
    expect(windows.map { |h| h["opens_at"] }).to eq(%w[08:00 16:00]), "windows must come back in clock order"
  end

  # ── A HALF-SAVED WEEK IS WORSE THAN AN UNCHANGED ONE ────────────────────
  #
  # The card goes on stating hours either way, so a partial save leaves it
  # advertising somebody's abandoned draft with nothing saying so.
  it "changes nothing at all when one row in the week is invalid" do
    put_week([ { day_of_week: 3, opens_at: "08:00", closes_at: "20:00" } ])
    expect(merchant.reload.opening_hours.count).to eq(1)

    # closes_at before opens_at — the model refuses it.
    put_week([
      { day_of_week: 4, opens_at: "08:00", closes_at: "20:00" },
      { day_of_week: 5, opens_at: "20:00", closes_at: "08:00" }
    ])

    expect(response).to have_http_status(:unprocessable_content)
    expect(json["code"]).to eq("invalid_opening_hours")
    expect(merchant.reload.opening_hours.count).to eq(1),
                                                   "the week was partly replaced, so the shop now advertises a draft"
    expect(merchant.opening_hours.first.day_of_week).to eq(3), "the ORIGINAL week must survive, not a fragment"
  end

  # ── WHAT THE CUSTOMER IS TOLD, ASSERTED END TO END ──────────────────────
  it "moves the next opening time the customer sees" do
    travel_to Time.zone.parse("2026-09-21 12:00:00 +0430") do
      put_week([ { day_of_week: (Time.zone.today + 1).wday, opens_at: "05:00", closes_at: "08:00" } ])
      merchant.update!(is_open: false)

      expect(merchant.reload.hours_known?).to be(true)
      expect(merchant.next_opens_at).to be_present
      expect(merchant.next_opens_at.strftime("%H:%M")).to eq("05:00"),
                                                          "the customer is told a different hour than the shop set"
    end
  end

  # Clearing the week is a real state: the card stops saying "opens at" and
  # starts saying "hours not listed — ring them".
  it "lets a shop clear its week, which the card reads as hours unknown" do
    put_week([ { day_of_week: 1, opens_at: "09:00", closes_at: "17:00" } ])
    expect(merchant.reload.hours_known?).to be(true)

    put_week([])

    expect(merchant.reload.hours_known?).to be(false)
  end

  it "records the week before and after" do
    put_week([ { day_of_week: 1, opens_at: "09:00", closes_at: "17:00" } ])

    expect {
      put_week([ { day_of_week: 1, opens_at: "11:00", closes_at: "23:00" } ])
    }.to change { AuditLog.where(action: "merchant.hours_updated").count }.by(1)

    log = AuditLog.where(action: "merchant.hours_updated").last
    expect(log.before.to_s).to include("09:00"), "the previous week is missing, so the row cannot be read"
    expect(log.after.to_s).to include("11:00")
  end

  it "is refused to somebody else's owner" do
    put_week([ { day_of_week: 1, opens_at: "09:00", closes_at: "17:00" } ])
    other = create(:user, :merchant_owner)
    create(:merchant, owner: other)

    put "/api/v1/merchant/opening_hours",
        params: { opening_hours: [] },
        headers: { "Authorization" => "Bearer #{UserSession.issue!(other).last}" }, as: :json

    expect(merchant.reload.opening_hours.count).to eq(1)
  end
end
