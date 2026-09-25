require "rails_helper"

# "WAS I PAID ON TUESDAY" — the statement by date.
#
# Asked for by karwan-42 (25 Sept 2026): paging back one screen at a time on
# metered data to find one entry is hunting. A statement-period picker needs
# the endpoint to take dates. Days are KABUL days, because that is the day a
# courier means.
RSpec.describe "The wallet statement by date", type: :request do
  let(:courier) { create(:user, :courier) }
  let(:wallet) { courier.courier_wallet }
  let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(courier).last}" } }

  def json = JSON.parse(response.body)
  def notes = json["wallet_entries"].map { _1["note"] }
  def entry_at(time, note) = travel_to(time) { wallet.record_entry!(kind: :top_up, amount: 100, note: note) }

  let(:kabul) { ActiveSupport::TimeZone["Asia/Kabul"] }

  before do
    entry_at(kabul.parse("2026-09-21 23:59:30"), "monday late")
    # 00:00:30 Kabul on Tuesday is 19:30 UTC on MONDAY: the day must be Kabul's.
    entry_at(kabul.parse("2026-09-22 00:00:30"), "tuesday early")
    entry_at(kabul.parse("2026-09-22 23:59:30"), "tuesday late")
    entry_at(kabul.parse("2026-09-23 00:00:30"), "wednesday early")
  end

  it "answers one Kabul day, both ends of it and nothing else" do
    get "/api/v1/courier/wallet/entries", params: { from: "2026-09-22", to: "2026-09-22" }, headers: auth

    expect(notes).to eq([ "tuesday late", "tuesday early" ])
  end

  it "takes either end alone" do
    get "/api/v1/courier/wallet/entries", params: { from: "2026-09-23" }, headers: auth
    expect(notes).to eq([ "wednesday early" ])

    get "/api/v1/courier/wallet/entries", params: { to: "2026-09-21" }, headers: auth
    expect(notes).to eq([ "monday late" ])
  end

  it "is the whole statement with neither, as before" do
    get "/api/v1/courier/wallet/entries", headers: auth

    expect(notes.size).to eq(4)
  end

  # A picker sends these, so a bad one is the app's bug, not a sentence.
  it "refuses a date that is not one, including one that only looks like one" do
    %w[tuesday 2026-9-22 2026-02-30].each do |bad|
      get "/api/v1/courier/wallet/entries", params: { from: bad }, headers: auth

      expect(response).to have_http_status(:bad_request), "#{bad} was accepted"
      expect(json["code"]).to eq("bad_request")
    end
  end

  it "never shows another courier's entries" do
    other = create(:user, :courier)
    travel_to(kabul.parse("2026-09-22 12:00")) { other.courier_wallet.record_entry!(kind: :top_up, amount: 5, note: "not yours") }

    get "/api/v1/courier/wallet/entries", params: { from: "2026-09-22", to: "2026-09-22" }, headers: auth

    expect(notes).not_to include("not yours")
  end
end
