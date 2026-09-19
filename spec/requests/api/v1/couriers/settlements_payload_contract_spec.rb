require "rails_helper"

# THE SHAPE A CLIENT PARSES AGAINST, kept honest by a fixture on disk.
#
# The mobile session declined to write a settlements parser because the payload
# had never been SEEN — only described. A description is an intention; a
# response is a fact, and the two drift silently. So the fact is committed at
# `spec/fixtures/files/courier_wallet_settlements.json` and this example fails
# the moment the API stops producing it.
#
# It covers all THREE variance states deliberately, because a client must
# render each and a fixture with only the happy one teaches the wrong shape:
#   short (counted < expected), balanced (equal), and over (counted > expected).
#
# WHAT THIS PROTECTS, in the client's terms:
#   · every money field is a STRING ("-50.0"), not a number. A client doing
#     `variance > 0` on it compares strings and is wrong for negatives.
#   · `note` is nullable and carries Pashto — encoding is part of the contract.
#   · the list is newest-first, and the envelope is `settlements` + `meta`.
RSpec.describe "Api::V1::Couriers::Wallet settlements payload", type: :request do
  let(:courier) { create(:user, :courier) }
  let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(courier).last}" } }
  let(:fixture) do
    JSON.parse(Rails.root.join("spec/fixtures/files/courier_wallet_settlements.json").read)
  end

  before do
    create(:settlement, :short, courier: courier, settled_at: Time.zone.parse("2026-09-17 18:30:00 +0430"),
                                note: "شپږ زره افغانۍ کمې وې")
    create(:settlement, courier: courier, settled_at: Time.zone.parse("2026-09-18 18:30:00 +0430"), note: nil)
    create(:settlement, :over, courier: courier, settled_at: Time.zone.parse("2026-09-19 18:30:00 +0430"),
                               counted_by_name: "Zarmina (Kabul office)", note: "extra found in the bag")
  end

  it "matches the committed fixture exactly, field for field" do
    get "/api/v1/courier/wallet/settlements", headers: auth

    body = JSON.parse(response.body)
    # Ids are database-assigned; the fixture numbers them 1..n in the same order.
    body["settlements"].each_with_index { |s, i| s["id"] = i + 1 }

    expect(body).to eq(fixture),
                    "the settlements payload changed. If that was deliberate, regenerate " \
                    "spec/fixtures/files/courier_wallet_settlements.json and tell the mobile session — " \
                    "a client is parsing this shape."
  end

  # Asserted separately from the equality above, because an equality failure
  # says "something moved" and this says WHICH property broke. A client reading
  # these as numbers is the likeliest misuse, so it is named rather than implied.
  it "sends every money field as a string, so a client cannot compare them numerically by accident" do
    get "/api/v1/courier/wallet/settlements", headers: auth

    JSON.parse(response.body)["settlements"].each do |s|
      %w[expected_amount counted_amount variance].each do |field|
        expect(s[field]).to be_a(String), "#{field} is #{s[field].class}, not a String"
      end
    end
  end

  # The fixture would be a poor teacher with only balanced rows in it.
  it "carries all three variance states, so the fixture teaches every case" do
    get "/api/v1/courier/wallet/settlements", headers: auth

    states = JSON.parse(response.body)["settlements"].map { |s| [ s["balanced"], s["short"] ] }
    expect(states).to contain_exactly([ false, true ], [ true, false ], [ false, false ])
  end
end
