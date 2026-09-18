require "rails_helper"

# ═══ IS A RIDER COMING? THE BOARD COULD NOT TELL ═══════════════════════════
#
# Three states looked identical on the merchant's board, and three inert cards
# are visible in the tablet screenshot:
#
#   1. ready, nobody assigned    — the shop waits on US, and we look bad
#   2. ready, a courier assigned — the shop should expect somebody
#   3. picked up                 — collected; PRODUCT.md:75 keeps the column
#
# The board view served `minutes_in_state`, which answers HOW LONG, and nothing
# that answered WHETHER. A number climbing with no rider is the case that
# generates the phone call — and the phone call is the product working, so the
# board has to be able to show it.
#
# ── PRODUCT.md:75 SETTLED THE THIRD ONE, NOT A PREFERENCE ────────────────
#
# "Order board — columns or sections: new, preparing, ready, **picked up**." So
# a collected order does not leave the board. The shop's job ends at the door;
# its cash reconciliation does not, and `paid_at` is on the same payload.
RSpec.describe "Api::V1::Merchants board states", type: :request do
  def json
    JSON.parse(response.body)
  end

  let(:owner) { create(:user, :merchant_owner) }
  let!(:merchant) { create(:merchant, owner: owner, is_open: true) }
  let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(owner).last}" } }

  def card_for(order)
    get "/api/v1/merchant/orders", headers: auth
    json.fetch("orders").find { |o| o["code"] == order.code }
  end

  it "says nobody is coming yet for a ready order with no courier" do
    order = create(:order, :ready, merchant: merchant, courier: nil)

    card = card_for(order)
    expect(card["status"]).to eq("ready")
    expect(card).to have_key("courier"), "the board cannot tell whether a rider is coming"
    expect(card["courier"]).to be_nil
  end

  it "names the rider once one is assigned, so the shop expects somebody" do
    courier = create(:user, :courier, name: "Ahmad Shah", phone: "+93700111222")
    order = create(:order, :ready, merchant: merchant, courier: courier)

    card = card_for(order)
    expect(card.dig("courier", "name")).to eq("Ahmad")
    expect(card.dig("courier", "phone")).to eq("+93700111222")
  end

  # THE DISTINCTION THE BOARD IS FOR. Both orders are `ready`; the cards must
  # differ, and a payload that collapses them is what made three cards inert.
  it "distinguishes the two ready states from each other" do
    waiting = create(:order, :ready, merchant: merchant, courier: nil)
    coming = create(:order, :ready, merchant: merchant, courier: create(:user, :courier))

    get "/api/v1/merchant/orders", headers: auth
    cards = json.fetch("orders").index_by { |o| o["code"] }

    expect(cards[waiting.code]["status"]).to eq(cards[coming.code]["status"])
    expect(cards[waiting.code]["courier"]).to be_nil
    expect(cards[coming.code]["courier"]).to be_present,
                                            "two ready orders render identically — one has a rider and one does not"
  end

  # PRODUCT.md:75 names "picked up" as a column, so the card stays. The shop's
  # cash reconciliation outlives the handover at the door.
  it "keeps a collected order on the board, with the rider who took it" do
    courier = create(:user, :courier, name: "Ahmad Shah")
    order = create(:order, :picked_up, merchant: merchant, courier: courier)

    card = card_for(order)
    expect(card).to be_present, "a collected order vanished from the board — PRODUCT.md:75 keeps that column"
    expect(card["status"]).to eq("picked_up")
    expect(card.dig("courier", "name")).to eq("Ahmad")
  end

  # ── WHAT THE SHOP MAY NOT KNOW ───────────────────────────────────────────
  #
  # A first name and a number to ring meets the need. A surname and a position
  # do not: a courier's live movements on a counter tablet is a person tracked
  # at work by somebody who is not their employer.
  it "gives a first name and a number, and not a surname or a position" do
    courier = create(:user, :courier, name: "Ahmad Shah", phone: "+93700111222")
    courier.courier_profile.update!(last_latitude: 34.5553, last_longitude: 69.2075)
    order = create(:order, :ready, merchant: merchant, courier: courier)

    card = card_for(order)

    expect(card["courier"].keys).to match_array(%w[name phone])
    expect(response.body).not_to include("Shah"), "the courier's surname reached a counter tablet"
    expect(response.body).not_to include("34.5553"), "the courier's position reached a counter tablet"
  end

  # `minutes_in_state` answers HOW LONG and the courier field answers WHETHER.
  # Neither alone is the alarming case; the pair is.
  it "carries the age beside it, so a climbing number means something" do
    order = create(:order, :ready, merchant: merchant, courier: nil)

    expect(card_for(order)["minutes_in_state"]).to be_present
  end
end
