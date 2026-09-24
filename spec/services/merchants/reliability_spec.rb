require "rails_helper"

# ═══ WHICH SHOP TO RING, WHICH IS NOT THE SAME QUESTION AS WHY ORDERS FAIL ══
#
# `TRUST_AND_REPUTATION.md` §5-B, on the case it calls **THE DAMAGING ONE**:
# *"What is missing is that cancellation reasons should be tracked per
# restaurant, so a restaurant cancelling a fifth of its orders is visible before
# its customers leave."* And §5-C: *"No penalty does not mean no visibility...
# Visibility is not a penalty, and the data is already recorded."*
#
# It was recorded and nothing read it per shop. `Admin::ReportsController`
# counts reasons across the platform — that answers "why do orders fail" and
# cannot answer "which shop should I ring", and the second is the one
# Hamma9900 acts on because he knows all ten personally.
#
# ── EVERY EXAMPLE HERE EXISTS TO SEPARATE TWO THINGS THAT LOOK ALIKE ──────
#
# The failure this guards is the one the platform report already records
# making: *"three shops never looked at the tablet and one shop made a
# decision. Added together the page says four shops keep closing early, and the
# owner rings four restaurants about a problem three of them do not have."*
RSpec.describe Merchants::Reliability do
  let(:merchant) { create(:merchant) }
  let(:owner) { create(:user, :merchant_owner) }
  let(:customer) { create(:user, :customer) }
  let(:admin) { AdminUser.create!(name: "Ops", email: "rel@karwan.af", password: "a-long-test-password") }

  def order_at(merchant, placed_at: 1.hour.ago)
    create(:order, :with_items, merchant: merchant, customer: customer, placed_at: placed_at)
  end

  # The shop answered and said no — the sheet's own reasons.
  def refused!(reason, merchant: self.merchant, placed_at: 1.hour.ago)
    order = order_at(merchant, placed_at: placed_at)
    order.transition_to!(:rejected, actor: owner, actor_role: :merchant_owner)
    order.update!(rejection_reason: reason)
    order
  end

  # Nobody touched the tablet. Exactly what `Dispatch::JobTimeoutsJob#close!`
  # does: a nil actor, and `no_answer`.
  def never_answered!(merchant: self.merchant, placed_at: 1.hour.ago)
    order = order_at(merchant, placed_at: placed_at)
    order.transition_to!(:rejected, actor: nil, actor_role: :admin,
                                    reason: "timed out in placed with no response")
    order.update!(rejection_reason: :no_answer)
    order
  end

  # Taken, then dropped. §5-B's case, and the state machine gives it to
  # `merchant_owner` from `accepted` and from `preparing`.
  def cancelled_after_accepting!(by: :merchant_owner, merchant: self.merchant)
    order = order_at(merchant)
    order.transition_to!(:accepted, actor: owner, actor_role: :merchant_owner)
    if by == :admin
      order.transition_to!(:cancelled, actor: nil, admin_user: admin, actor_role: :admin)
    else
      order.transition_to!(:cancelled, actor: owner, actor_role: :merchant_owner)
    end
    order.update!(cancellation_reason: :merchant_unavailable)
    order
  end

  def delivered!(merchant: self.merchant)
    create(:order, :with_items, :delivered, merchant: merchant, customer: customer,
                                            placed_at: 1.hour.ago, delivered_at: 30.minutes.ago)
  end

  def figures = described_class.for(merchant)

  describe "the three outcomes, which are three different phone calls" do
    it "counts a shop's own refusals by the reason it gave" do
      2.times { refused!(:out_of_stock) }
      refused!(:too_busy)

      expect(figures[:refused]).to eq([ [ "out_of_stock", 2 ], [ "too_busy", 1 ] ])
    end

    # THE ONE THAT MATTERS, and the one the platform report was built to avoid.
    it "does not count an order nobody answered as a decision the shop made" do
      refused!(:closing)
      3.times { never_answered! }

      expect(figures[:refused]).to eq([ [ "closing", 1 ] ]),
                                   "the timed-out orders are being counted as the shop's decisions"
      expect(figures[:never_answered]).to eq(3),
                                          "a tablet nobody watches is the finding, and it is not on the page"
    end

    # ── WHY THE ACTOR IS CHECKED AND NOT ONLY THE REASON ───────────────────
    #
    # A timeout writes `no_answer`, which is not one of the shop's four, so the
    # reason column alone happens to separate the two TODAY — and the first
    # version of this file proved nothing about the actor filter because of it:
    # removing `by_merchant_owner` left every example green.
    #
    # `Order::TRANSITIONS` gives `rejected` to an **admin** as well
    # (`placed: { rejected: [merchant_owner, admin] }`), with no console route
    # for it yet. An operator rejecting on the phone — *"they rang, they are out
    # of chicken"* — writes a MERCHANT reason with an operator as the actor, and
    # without the filter that is filed as a decision the shop made.
    it "does not file an operator's rejection as the shop's own decision" do
      order = order_at(merchant)
      order.transition_to!(:rejected, actor: nil, admin_user: admin, actor_role: :admin)
      order.update!(rejection_reason: :out_of_stock)
      refused!(:out_of_stock)

      expect(figures[:refused]).to eq([ [ "out_of_stock", 1 ] ]),
                                   "an operator's rejection is being counted against the restaurant"
    end

    it "counts an order taken and then dropped separately from one refused at the door" do
      refused!(:out_of_stock)
      cancelled_after_accepting!

      expect(figures[:cancelled_after_accepting]).to eq(1)
      expect(figures[:refused].sum { |_r, n| n }).to eq(1),
                                                    "a refusal and a cancellation after acceptance are not the same event"
    end

    # ── THE DISCRIMINATING INPUT, WITHOUT WHICH THE COUNT IS WORTHLESS ─────
    #
    # A customer changing their mind is the COMMONEST cancellation there is.
    # Counting it here would make every busy restaurant look unreliable and the
    # figure worth nothing — and it is the one mistake that would still leave
    # every other example in this file green.
    it "does not count a customer changing their mind as the shop's failure" do
      3.times do
        order = order_at(merchant)
        order.transition_to!(:cancelled, actor: customer, actor_role: :customer)
        order.update!(cancellation_reason: :customer_changed_mind)
      end
      delivered!

      expect(figures[:cancelled_after_accepting]).to be_zero,
                                                    "the commonest cancellation of all is being blamed on the restaurant"
      expect(figures[:unfulfilled]).to be_zero
      expect(figures[:orders]).to eq(4), "it is still an order the shop was sent"
    end

    # The merchant app has no cancel route, so this is how §5-C actually
    # happens: the shop rings the office and an operator does it.
    it "counts an operator's cancellation made on the shop's behalf" do
      cancelled_after_accepting!(by: :admin)

      expect(figures[:cancelled_after_accepting]).to eq(1),
                                                     "a shop that rings the office to cancel is still a shop that cancelled"
    end
  end

  describe "the denominator, which is the whole point" do
    it "counts every order the shop was sent, including the ones that went well" do
      3.times { delivered! }
      refused!(:too_busy)

      expect(figures[:orders]).to eq(4)
      expect(figures[:unfulfilled]).to eq(1)
      expect(figures[:unfulfilled_rate]).to eq(25.0)
    end

    # "A restaurant cancelling a fifth of its orders" is the document's own
    # sentence, and a fifth is a rate.
    it "reports a fifth as a fifth" do
      4.times { delivered! }
      refused!(:out_of_stock)

      expect(figures[:unfulfilled_rate]).to eq(20.0)
    end

    # A new shop with nothing to show is not a shop with a perfect record.
    it "says nothing rather than 0% when the shop has had no orders" do
      expect(figures[:orders]).to be_zero
      expect(figures[:unfulfilled_rate]).to be_nil,
                                           "0% next to a shop nobody has ordered from is a claim the data cannot make"
    end

    it "does not count another shop's orders" do
      other = create(:merchant)
      3.times { refused!(:closing, merchant: other) }
      delivered!

      expect(figures[:orders]).to eq(1)
      expect(figures[:unfulfilled]).to be_zero
    end

    it "does not count an order older than the window" do
      refused!(:too_busy, placed_at: 40.days.ago)
      delivered!

      expect(figures[:orders]).to eq(1)
      expect(figures[:unfulfilled]).to be_zero
    end

    it "does not count an order that is still running" do
      order_at(merchant)

      expect(figures[:orders]).to eq(1)
      expect(figures[:unfulfilled]).to be_zero, "a live order has not gone wrong yet"
    end
  end

  # ── THE ASSUMPTION THAT REPLACED A FILTER THAT COULD NOT FIRE ────────────
  #
  # `cancelled_after_accepting` does NOT exclude the customer's own
  # cancellations, and the obvious version did. It could never have removed a
  # row: `Order::TRANSITIONS` gives `cancelled` to a customer from **`placed`
  # only**, so an order with `accepted_at` set is not one they could have
  # cancelled. A condition that cannot fire is a check that cannot fail.
  #
  # So the assumption is pinned here instead. If the state machine ever lets a
  # customer cancel later, this fails and names the method to change.
  describe "the state machine assumption it rests on" do
    it "lets a customer cancel only before the shop has accepted" do
      states = Order::TRANSITIONS.select { |_from, to| to[:cancelled]&.include?(:customer) }

      expect(states.keys).to eq([ :placed ]),
                             "a customer can now cancel after acceptance, so " \
                             "Merchants::Reliability#cancelled_after_accepting is counting it as the shop's"
    end

    # And the other half: the shop itself may cancel while cooking. That is
    # §5-C's case, the state machine allows it, and the merchant API has no
    # route for it — recorded in docs/NOTES.md rather than invented here.
    it "lets the shop cancel after accepting, which is the case being counted" do
      expect(Order::TRANSITIONS[:accepted][:cancelled]).to include(:merchant_owner)
      expect(Order::TRANSITIONS[:preparing][:cancelled]).to include(:merchant_owner)
    end
  end

  # ══ THE RANKING, WHICH IS THE READING §5-B ACTUALLY ASKS FOR ═════════════
  #
  # *"Visible before its customers leave."* A figure on one shop's own console
  # page is only visible to somebody who already suspects that shop.
  describe ".ranked" do
    def busy_shop!(name, orders:, refused: 0)
      shop = create(:merchant, name: name)
      refused.times { refused!(:out_of_stock, merchant: shop) }
      (orders - refused).times { delivered!(merchant: shop) }
      shop
    end

    it "puts the worst rate first, with its own denominator beside it" do
      bad = busy_shop!("bad", orders: 10, refused: 4)
      mild = busy_shop!("mild", orders: 10, refused: 1)

      rows = described_class.ranked

      expect(rows.map { |r| r[:merchant_id] }).to eq([ bad.id, mild.id ])
      expect(rows.first).to include(orders: 10, unfulfilled: 4, unfulfilled_rate: 40.0)
    end

    # A shop with three orders and one refusal is at 33% and means nothing.
    it "leaves out a shop with too few orders to say anything about" do
      busy_shop!("thin", orders: 3, refused: 1)
      steady = busy_shop!("steady", orders: 10, refused: 2)

      expect(described_class.ranked.map { |r| r[:merchant_id] }).to eq([ steady.id ]),
                                                                    "one bad evening at a new shop is not a reason to ring it"
    end

    it "leaves out a shop that lost nothing" do
      busy_shop!("clean", orders: 8)

      expect(described_class.ranked).to be_empty, "a page of shops with nothing wrong is a page nobody reads"
    end

    # ── THE GUARD THAT MATTERS MOST: ONE QUESTION, ONE ANSWER ──────────────
    #
    # The ranking and the shop's own page are two readings of the same
    # definitions. If they are ever written as two sets of queries they will
    # disagree about a real restaurant, and the person holding the phone will
    # not know which number to believe.
    it "agrees with the per-shop reading, shop for shop" do
      shop = create(:merchant, name: "mixed")
      2.times { refused!(:too_busy, merchant: shop) }
      never_answered!(merchant: shop)
      cancelled_after_accepting!(merchant: shop)
      6.times { delivered!(merchant: shop) }

      row = described_class.ranked.detect { |r| r[:merchant_id] == shop.id }
      alone = described_class.for(shop)

      expect(row[:orders]).to eq(alone[:orders])
      expect(row[:unfulfilled]).to eq(alone[:unfulfilled])
      expect(row[:unfulfilled_rate]).to eq(alone[:unfulfilled_rate])
      expect(row[:never_answered]).to eq(alone[:never_answered])
      expect(row[:cancelled_after_accepting]).to eq(alone[:cancelled_after_accepting])
      expect(row[:refused]).to eq(alone[:refused].sum { |_reason, n| n })
    end

    # ── AND IT MUST NOT COST A QUERY PER SHOP ──────────────────────────────
    #
    # `docs/NOTES.md` records the public catalog costing 102 queries because a
    # per-item lookup sat inside a loop. A report is exactly where that goes
    # unnoticed, so this asserts the cost does not GROW rather than asserting a
    # threshold.
    it "costs the same number of queries whatever the number of shops" do
      3.times { |i| busy_shop!("shop #{i}", orders: 6, refused: 2) }
      few = count_queries { described_class.ranked }

      3.upto(8) { |i| busy_shop!("shop #{i}", orders: 6, refused: 2) }
      many = count_queries { described_class.ranked }

      expect(many).to eq(few),
                      "the ranking costs #{many} queries at nine shops and #{few} at three — it is per-merchant"
    end

    def count_queries
      queries = []
      subscription = ActiveSupport::Notifications.subscribe("sql.active_record") do |_, _, _, _, payload|
        queries << payload[:sql] unless payload[:name].to_s.match?(/SCHEMA|TRANSACTION/)
      end
      yield
      queries.size
    ensure
      ActiveSupport::Notifications.unsubscribe(subscription)
    end
  end

  describe "the console line" do
    it "leads with the rate, because the rate is the sentence" do
      4.times { delivered! }
      refused!(:out_of_stock)

      expect(merchant.reliability_summary).to start_with("20.0% of 5 orders")
      expect(merchant.reliability_summary).to include("1 refused (out of stock ×1)")
    end

    it "says so plainly when nothing was lost" do
      2.times { delivered! }

      expect(merchant.reliability_summary).to eq("2 orders, none lost")
    end

    it "does not claim a record for a shop with no orders" do
      expect(merchant.reliability_summary).to eq("no orders in the last 30 days")
    end

    it "keeps the three outcomes apart in the words it uses" do
      delivered!
      refused!(:too_busy)
      never_answered!
      cancelled_after_accepting!

      summary = merchant.reliability_summary

      expect(summary).to include("1 refused", "1 never answered", "1 cancelled after accepting")
    end
  end
end
