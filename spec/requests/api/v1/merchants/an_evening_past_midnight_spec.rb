require "rails_helper"

# A SHOP OPEN UNTIL 01:00 CAN SAY SO (Hamma9900's platform, Hamma9901's ruling,
# 25 Sept 2026).
#
# Stored implicitly (close earlier than open = the next day), served
# explicitly (`closes_next_day`). The window belongs to the day it opens. The
# look-back rule is the server's alone: the app computes no "open now", it
# renders `next_opens_at`. So at 00:30 on Tuesday, Monday's 23:00-01:00 has to
# count HERE. Overlaps are refused across the whole week, because once a
# window crosses midnight, Monday's reaches into Tuesday.
#
# Dates: 21 Sept 2026 is a Monday. Kabul is UTC+4:30, so 00:30 Tuesday in
# Kabul is 20:00 Monday UTC, still Monday in Paris and in New York too
# (bin/rspec-in-another-zone reruns this file there).
RSpec.describe "An evening past midnight", type: :request do
  let(:owner) { create(:user, :merchant_owner) }
  let!(:merchant) { create(:merchant, owner: owner, is_open: false) }
  let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(owner).last}" } }

  MONDAY, TUESDAY, SATURDAY, SUNDAY = 1, 2, 6, 0

  def json = JSON.parse(response.body)
  def row(day, opens, closes) = { day_of_week: day, opens_at: opens, closes_at: closes }

  def save_week(*rows)
    put "/api/v1/merchant/opening_hours", params: { opening_hours: rows }, headers: auth, as: :json
  end

  def public_merchant
    get "/api/v1/public/merchants/#{merchant.id}"
    JSON.parse(response.body)["merchant"]
  end

  describe "saving" do
    it "accepts a window that closes the next day, and says so" do
      save_week(row(MONDAY, "23:00", "01:00"), row(TUESDAY, "09:00", "17:00"))

      expect(response).to have_http_status(:ok), response.body
      served = json.values.find { _1.is_a?(Array) }
      expect(served.map { _1.slice("day_of_week", "opens_at", "closes_at", "closes_next_day") }).to eq([
        { "day_of_week" => 1, "opens_at" => "23:00", "closes_at" => "01:00", "closes_next_day" => true },
        { "day_of_week" => 2, "opens_at" => "09:00", "closes_at" => "17:00", "closes_next_day" => false }
      ])
    end

    it "serves the same fact on the customer's shop page" do
      save_week(row(MONDAY, "23:00", "01:00"))

      expect(public_merchant["opening_hours"].first).to include("closes_next_day" => true)
    end

    # "Twenty-four hours" and "zero hours" are the same input.
    it "still refuses a close equal to the open, naming the row" do
      save_week(row(MONDAY, "09:00", "17:00"), row(TUESDAY, "09:00", "09:00"))

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("code" => "invalid_opening_hours", "row" => 1, "reason" => "same_open_and_close")
      expect(merchant.opening_hours.count).to eq(0) # the whole week rolled back
    end

    it "refuses two windows that overlap on one day" do
      save_week(row(MONDAY, "09:00", "17:00"), row(MONDAY, "14:00", "20:00"))

      expect(json).to include("row" => 1, "reason" => "overlaps")
    end

    # A shop that shuts for the afternoon and reopens writes exactly this.
    it "accepts two windows that only touch" do
      save_week(row(MONDAY, "09:00", "14:00"), row(MONDAY, "14:00", "18:00"))

      expect(response).to have_http_status(:ok)
    end

    it "refuses a morning that collides with the night before" do
      save_week(row(MONDAY, "23:00", "01:00"), row(TUESDAY, "00:30", "08:00"))

      expect(json).to include("row" => 1, "reason" => "overlaps")
    end

    it "refuses the same collision across the end of the week" do
      save_week(row(SATURDAY, "23:00", "01:00"), row(SUNDAY, "00:30", "08:00"))

      expect(json).to include("row" => 1, "reason" => "overlaps")
    end

    # The console writes rows one at a time and has no form-side guard.
    it "refuses an overlap written straight to the table, as the console does" do
      merchant.opening_hours.create!(row(MONDAY, "23:00", "01:00"))
      clash = merchant.opening_hours.build(row(TUESDAY, "00:30", "08:00"))

      expect(clash).not_to be_valid
      expect(clash.errors.details[:opens_at]).to include(error: :overlaps)
    end
  end

  describe "the look-back, which is the server's alone" do
    before { save_week(row(MONDAY, "23:00", "01:00")) }

    # The shop's toggle is off (is_open: false), so next_opens_at speaks. Inside
    # the posted hours it must say NOTHING (a shopkeeper who shut early), not
    # point at next Monday while the posted window is still running.
    it "treats 00:30 on Tuesday as inside Monday's window" do
      travel_to(Time.utc(2026, 9, 21, 20, 0)) do # Tuesday 00:30 in Kabul
        shop = public_merchant
        expect(shop["hours_known"]).to be true
        expect(shop["next_opens_at"]).to be_nil
      end
    end

    it "points at next Monday once Monday's window has closed" do
      travel_to(Time.utc(2026, 9, 21, 21, 30)) do # Tuesday 02:00 in Kabul
        expect(public_merchant["next_opens_at"]).to start_with("2026-09-28T23:00:00.000+04:30")
      end
    end

    # The reliability report asks with a stored instant; the answer must be
    # Kabul's, whatever zone the instant carries.
    it "answers in Kabul for an instant given in UTC" do
      rows = merchant.opening_hours.to_a

      expect(Merchant.open_per_schedule?(Time.utc(2026, 9, 21, 20, 0), rows)).to be true
      expect(Merchant.open_per_schedule?(Time.utc(2026, 9, 21, 21, 30), rows)).to be false
    end
  end
end
