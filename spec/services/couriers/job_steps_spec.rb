require "rails_helper"

# ── WHEN HE DID IT, NOT ONLY THAT HE DID ───────────────────────────────────
#
# The stepper showed ticks and no times while the CUSTOMER's timeline, built
# from the same transitions, showed both. That asymmetry is the wrong way round
# for the one party who is out of pocket: the courier advances his own money to
# the restaurant and is repaid by the customer, so he is the person who may
# later have to prove when he paid.
RSpec.describe Couriers::JobSteps do
  let(:courier) { create(:user, :courier) }
  let(:merchant) { create(:merchant) }

  def delivery
    order = create(:order, :with_items, :ready, merchant: merchant, courier: courier)
    order
  end

  def steps_for(job) = described_class.new(job).call

  def step(job, key) = steps_for(job).find { |s| s[:key] == key }

  it "stamps a completed action step from the transition log" do
    order = delivery
    travel_to Time.zone.parse("2026-09-21 18:30:00 +0430") do
      order.transition_to!(:picked_up, actor: courier, actor_role: :courier)
    end

    paid = step(order, "pay_merchant")
    expect(paid[:completed]).to be(true), "nothing to time if the step is not complete"
    expect(paid[:at]).to be_present
    expect(paid[:at].strftime("%H:%M")).to eq("18:30")
  end

  # ── THE TWO SCREENS MUST NOT DISAGREE ABOUT A HANDOVER OF CASH ──────────
  #
  # Same source, asserted as equality rather than as "both look plausible".
  # Two computations of one moment is how two screens come to disagree.
  it "agrees exactly with the customer's timeline" do
    order = delivery
    order.transition_to!(:picked_up, actor: courier, actor_role: :courier)

    from_timeline = order.transitions.chronological.find { |t| t.to_status == "picked_up" }.created_at

    expect(step(order, "pay_merchant")[:at]).to eq(from_timeline)
  end

  # "Go to the merchant" carries no transition — it is complete because the
  # step it leads to is. The only time available is the PAYMENT's, and putting
  # it here would report the moment he handed over money as the moment he
  # arrived. Different facts; he may be asked about both.
  it "gives a navigation step no time, even once it is complete" do
    order = delivery
    order.transition_to!(:picked_up, actor: courier, actor_role: :courier)

    navigation = step(order, "go_to_merchant")
    expect(navigation[:completed]).to be(true), "the navigation step must be complete or this proves nothing"
    expect(navigation[:at]).to be_nil,
                              "the arrival was stamped with the payment's time — two different facts"
  end

  it "gives an unfinished step no time" do
    order = delivery

    expect(step(order, "pay_merchant")[:completed]).to be(false)
    expect(step(order, "pay_merchant")[:at]).to be_nil
  end

  # The question is when it FIRST happened. A later transition overwriting it
  # would give an answer that always looks recent — the same reasoning that
  # keeps the merchant's acknowledgement on its first tap.
  it "keeps the earliest time when a status is reached more than once" do
    order = delivery
    first = Time.zone.parse("2026-09-21 18:30:00 +0430")
    travel_to(first) { order.transition_to!(:picked_up, actor: courier, actor_role: :courier) }
    order.transitions.create!(from_status: "picked_up", to_status: "picked_up",
                              actor: courier, actor_role: :courier, created_at: first + 2.hours)

    expect(step(order, "pay_merchant")[:at].to_i).to eq(first.to_i)
  end

  it "stamps a ride's steps too" do
    trip = create(:trip, :accepted, courier: courier)
    travel_to(Time.zone.parse("2026-09-21 09:15:00 +0430")) do
      trip.transition_to!(:arrived, actor: courier, actor_role: :courier)
    end

    arrived = steps_for(trip).find { |s| s[:status_after] == "arrived" }
    expect(arrived[:at]&.strftime("%H:%M")).to eq("09:15")
  end

  # Guards the guard: if the step list ever stopped carrying `at` at all, the
  # nil-expectations above would pass while asserting nothing.
  it "carries the key on every step, so the nil assertions mean something" do
    order = delivery

    expect(steps_for(order)).to all(have_key(:at))
  end
end
