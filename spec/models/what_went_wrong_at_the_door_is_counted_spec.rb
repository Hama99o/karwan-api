require "rails_helper"

# ═══ WHAT WENT WRONG AT THIS PERSON'S DOOR — OR KERB — COUNTED ═════════════
#
# `TRUST_AND_REPUTATION.md` §2: *"The customer is not rated. What went wrong is
# COUNTED"*, and the courier's problem reports *"should accumulate against the
# customer."* `MONEY_AND_SETTLEMENT.md` §7 says the same of a ride: *"The
# passenger gets a strike."*
#
# `User#delivery_failures` shipped on 21 Sept with no spec of its own, and read
# `orders` alone — so a passenger who no-showed four drivers had a clean record
# and was missing from the console's `had_a_failure` list.
#
# ── THE DISCRIMINATING INPUTS ARE IN THIS FILE ON PURPOSE ─────────────────
#
# - The person is also a COURIER with a failed trip he drove. `trips` and
#   `courier_trips` are one letter of intent apart; counting the second would
#   put a driver's own bad night on his record as a passenger.
# - Another customer's failures sit in the same table, so a count that forgot
#   to scope to the person fails.
# - A failure with no reason, and one outside the 30-day window, are both
#   present, so the filters on them are exercised rather than assumed.
RSpec.describe "what went wrong at a person's door is counted", type: :model do
  let(:person) { create(:user, :courier) }
  let(:merchant) { create(:merchant) }

  def failed_order(reason, customer: person, at: 2.days.ago)
    create(:order, :with_items, :placed, merchant: merchant, customer: customer)
      .tap { |o| o.update_columns(status: Order.statuses[:failed], failure_reason: reason, failed_at: at) }
  end

  def failed_trip(reason, passenger: person, courier: nil, at: 2.days.ago)
    create(:trip, passenger: passenger, courier: courier)
      .tap { |t| t.update_columns(status: Trip.statuses[:failed], failure_reason: reason, failed_at: at) }
  end

  before do
    failed_order(:wrong_address)
    failed_order(:wrong_address, at: 45.days.ago)
    failed_order(nil)
    failed_trip(:passenger_no_show)
    failed_trip(:passenger_no_show)

    # Noise that must not land on this person.
    failed_order(:nobody_home, customer: create(:user, :customer))
    failed_trip(:passenger_unreachable, passenger: create(:user, :customer), courier: person)
  end

  it "counts the orders that failed at this person's door, by reason" do
    expect(person.delivery_failures).to eq("wrong_address" => 2)
    expect(person.recent_delivery_failures).to eq("wrong_address" => 1)
  end

  it "counts the rides that failed at this person's kerb, and not the ones he drove" do
    expect(person.ride_failures).to eq("passenger_no_show" => 2)
    expect(person.recent_ride_failures).to eq("passenger_no_show" => 2)
  end

  it "puts both on one line for the operator, with the recent count across both" do
    expect(person.delivery_failures_summary)
      .to eq("wrong address ×2, passenger no show ×2 — 3 in the last 30 days")
  end

  it "says none for a person with nothing recorded against them" do
    expect(create(:user, :customer).delivery_failures_summary).to eq("none")
  end

  # The console list and the summary line must agree about who has a record.
  # A person whose ONLY failures are rides is the case the old filter missed.
  it "lists a passenger whose only failures are rides in the console's filter" do
    rides_only = create(:user, :customer)
    failed_trip(:passenger_no_show, passenger: rides_only)
    clean = create(:user, :customer)

    listed = UserDashboard::COLLECTION_FILTERS.fetch(:had_a_failure).call(User.all)

    expect(listed).to include(person, rides_only)
    expect(listed).not_to include(clean)
    expect(rides_only.delivery_failures_summary).to start_with("passenger no show ×1")
  end
end
