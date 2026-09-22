require "rails_helper"

# ═══ WHY AN ORDER ENDED, AS A SHAPE A CLIENT CAN PARSE AGAINST ═════════════
#
# `settlements_payload_contract_spec.rb` states the argument and this follows
# it: *"A description is an intention; a response is a fact, and the two drift
# silently."*
#
# `ended_reason` is the subtlest contract in the API and the one a prose
# description cannot carry, because **prose has no way to say that null here and
# null there are different facts.** The fixture puts all of them in ONE
# response, three rows apart, where a client can see them together:
#
#   K000001  rejected   out_of_stock           ended_by "merchant_owner"
#   K000002  rejected   no_answer              ended_by "system"      ← a machine
#   K000003  cancelled  customer_changed_mind  ended_by "customer"
#   K000004  failed     nobody_home            ended_by "courier"
#   K000005  rejected   too_busy               ended_by NULL          ← nothing knows
#   K000006  delivered  ended_reason NULL                             ← nothing to explain
#   K000007  preparing  ended_reason NULL                             ← not over yet
#
# ── THE THREE DISTINCTIONS, AND WHAT EACH COSTS IF A CLIENT COLLAPSES IT ──
#
#   1. **`ended_by: "system"` vs `ended_by: null`.** A machine closed it, versus
#      nobody recorded who. Rendering the second as "cancelled by Karwan" tells
#      a customer something nothing in the data supports. `db/seeds/stress.rb`
#      writes rows of the second kind in bulk, so it is not hypothetical.
#   2. **`ended_reason: null` vs `ended_by: null`.** The whole object absent
#      means the order has not ended badly — delivered or still running. A null
#      INSIDE the object means it ended and the actor is unknown. A client
#      testing only `ended_reason?.ended_by` cannot tell a delivered order from
#      an unattributed rejection.
#   3. **`outcome` names which vocabulary `code` came from.** `rejected`,
#      `cancelled` and `failed` are three separate enums. One merged lookup
#      collides the first day two of them share a word.
#
# ── AND THE HARM CLASS THIS IS REALLY ABOUT ───────────────────────────────
#
# Every value here becomes a sentence shown to somebody whose dinner did not
# arrive. `AFGHAN_UX.md` §1 makes the code a key the client translates rather
# than a server-written string — so a client that maps the wrong key does not
# fail loudly, it says a confident wrong thing in Pashto.
RSpec.describe "the ended_reason contract", type: :request do
  let(:customer) { create(:user, :customer) }
  let(:merchant) { create(:merchant, name: "کباب شهر نو") }
  let(:owner) { create(:user, :merchant_owner) }
  let(:courier) { create(:user, :courier) }
  let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(customer).last}" } }
  let(:fixture) do
    JSON.parse(Rails.root.join("spec/fixtures/files/customer_orders_ended_reason.json").read)
  end

  # Fixed instant: `placed_at` is in the payload, so a live clock would make
  # every field drift and the fixture would have to be regenerated hourly.
  let(:evening_in_kabul) { Time.zone.parse("2026-09-22 20:00:00 +0430") }

  def base
    { customer: customer, merchant: merchant, items_total: 400, delivery_fee: 100,
      commission: 50, merchant_payout: 350, customer_total: 500, courier_fee: 100 }
  end

  def build_every_state!
    a = create(:order, :with_items, **base, code: "K000001", placed_at: 5.hours.ago)
    a.transition_to!(:rejected, actor: owner, actor_role: :merchant_owner)
    a.update!(rejection_reason: :out_of_stock)

    b = create(:order, :with_items, **base, code: "K000002", placed_at: 4.hours.ago)
    b.transition_to!(:rejected, actor: nil, actor_role: :admin, reason: "timed out")
    b.update!(rejection_reason: :no_answer)

    c = create(:order, :with_items, **base, code: "K000003", placed_at: 3.hours.ago)
    c.transition_to!(:cancelled, actor: customer, actor_role: :customer)
    c.update!(cancellation_reason: :customer_changed_mind)

    d = create(:order, :with_items, :picked_up, **base, code: "K000004", courier: courier,
                                                placed_at: 2.hours.ago)
    d.transition_to!(:failed, actor: courier, actor_role: :courier, reason: "nobody_home")
    d.update!(failure_reason: :nobody_home)

    # NOTHING recorded who — the shape `db/seeds/stress.rb` produces in bulk.
    e = create(:order, :with_items, **base, code: "K000005", placed_at: 90.minutes.ago)
    e.update_columns(status: Order.statuses[:rejected], rejected_at: Time.current,
                     rejection_reason: Order.rejection_reasons[:too_busy])

    create(:order, :with_items, :delivered, **base, code: "K000006", placed_at: 1.hour.ago,
                                            delivered_at: 30.minutes.ago)
    create(:order, :with_items, :preparing, **base, code: "K000007", placed_at: 20.minutes.ago)
  end

  def orders_by_code
    JSON.parse(response.body)["orders"].index_by { |order| order["code"] }
  end

  it "matches the committed fixture exactly, field for field" do
    travel_to evening_in_kabul do
      build_every_state!

      get "/api/v1/customer/orders", headers: auth

      body = JSON.parse(response.body)
      # ── A SEQUENCE NUMBER IS NOT A CONTRACT, AND PINNING ONE LIES ────────
      #
      # Every id here is database-assigned, and a Postgres sequence does NOT
      # roll back with the transaction — so it is wherever the examples that
      # ran before this one left it. This spec was GREEN ON ITS OWN and red in
      # a full directory run for exactly that reason: `merchant_id` came back
      # 1 alone and 71 after 70 other merchants. Same family as the constant
      # collision in `no_two_specs_share_a_constant_spec.rb`.
      #
      # `id` is renumbered because the ORDER of the rows is the contract and
      # the value is not. `merchant_id` is ASSERTED first and only then
      # normalised — that every row names the shop it came from is real
      # contract, and normalising it away unchecked would delete the only
      # thing the field is for.
      body["orders"].each_with_index do |order, i|
        expect(order["merchant_id"]).to eq(merchant.id), "row #{i} lost its shop"
        order["id"] = i + 1
        order["merchant_id"] = 1
      end

      expect(body).to eq(fixture),
                      "the ended_reason payload changed. If deliberate, regenerate " \
                      "spec/fixtures/files/customer_orders_ended_reason.json and tell the mobile session — " \
                      "a client renders these values to somebody whose dinner did not arrive."
    end
  end

  # ── 1 · A MACHINE DID IT vs NOBODY KNOWS ─────────────────────────────────
  it "distinguishes the system from an unrecorded actor" do
    travel_to evening_in_kabul do
      build_every_state!
      get "/api/v1/customer/orders", headers: auth
      orders = orders_by_code

      expect(orders["K000002"]["ended_reason"]["ended_by"]).to eq("system")
      expect(orders["K000005"]["ended_reason"]["ended_by"]).to be_nil
      expect(orders["K000005"]["ended_reason"]["code"]).to be_present,
                                                          "the order DID end — only the actor is unknown"
    end
  end

  # ── 2 · THE OBJECT ABSENT vs A NULL INSIDE IT ────────────────────────────
  it "sends no object at all for an order that did not end badly" do
    travel_to evening_in_kabul do
      build_every_state!
      get "/api/v1/customer/orders", headers: auth
      orders = orders_by_code

      expect(orders["K000006"]["ended_reason"]).to be_nil, "a delivered order has nothing to explain"
      expect(orders["K000007"]["ended_reason"]).to be_nil, "a running order has not ended"
      expect(orders["K000005"]["ended_reason"]).to be_a(Hash),
                                                  "an unattributed ending is still an ending — the object is present"
    end
  end

  # ── 3 · WHICH VOCABULARY THE CODE CAME FROM ──────────────────────────────
  it "names the outcome beside every code" do
    travel_to evening_in_kabul do
      build_every_state!
      get "/api/v1/customer/orders", headers: auth
      orders = orders_by_code

      expect(orders["K000001"]["ended_reason"]["outcome"]).to eq("rejected")
      expect(orders["K000003"]["ended_reason"]["outcome"]).to eq("cancelled")
      expect(orders["K000004"]["ended_reason"]["outcome"]).to eq("failed")

      # Each code belongs to its own enum, and the client must look it up there.
      expect(Order.rejection_reasons).to have_key(orders["K000001"]["ended_reason"]["code"])
      expect(Order.cancellation_reasons).to have_key(orders["K000003"]["ended_reason"]["code"])
      expect(Order.failure_reasons).to have_key(orders["K000004"]["ended_reason"]["code"])
    end
  end

  # The fixture must keep teaching all of it. A regeneration that quietly loses
  # a state leaves the client with a shape it will meet in production and has
  # never seen.
  it "keeps every state in the fixture" do
    reasons = fixture["orders"].map { |order| order["ended_reason"] }

    expect(reasons.count(&:nil?)).to eq(2), "the two 'nothing to explain' rows are gone"
    present = reasons.compact
    expect(present.map { |r| r["ended_by"] }).to include("system", nil, "merchant_owner", "customer", "courier")
    expect(present.map { |r| r["outcome"] }.uniq).to match_array(%w[rejected cancelled failed])
  end
end
