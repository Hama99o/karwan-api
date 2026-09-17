require "rails_helper"

# ORDERING FOR SOMEBODY ELSE — and the courier must ring THEM, not the booker.
#
# Hamma9900's scenario: he is at home and books a taxi, or a delivery, for
# somebody at an address that is not where he is standing. One person with a
# smartphone booking for a whole family is a PRIMARY use in this market
# (`AFGHAN_UX.md` §7 — phones are shared), not a convenience.
#
# The columns were always right: `orders.customer_phone` and
# `trips.passenger_phone` are separate from `customer_id`/`passenger_id`, and
# the address is a snapshot rather than a reference. What had no test was that
# THE STEP LIST READS THEM. If it ever fell back to `customer.phone`, a courier
# would ring the person who paid and stand outside the wrong gate — and both
# failures look like a courier problem from the outside.
RSpec.describe "a job booked for somebody else", type: :model do
  let(:booker) { create(:user, :customer, phone: "+93700000111", name: "احمد") }
  let(:merchant) { create(:merchant, latitude: 34.5553, longitude: 69.2075) }
  let(:category) { create(:catalog_category, merchant: merchant) }
  let!(:kabab) { create(:catalog_item, catalog_category: category, merchant: merchant, price: 400) }

  let(:order) do
    Orders::PlaceService.new(
      customer: booker, merchant: merchant,
      lines: [ { catalog_item_id: kabab.id, quantity: 1 } ],
      # HER house and HER number, not his.
      delivery_latitude: 34.5100, delivery_longitude: 69.1900,
      delivery_landmark_note: "شین دروازه، کوچه سوم، دروازه آبی",
      customer_phone: "+93700000222"
    ).call
  end

  def steps
    Couriers::JobSteps.new(order).call.index_by { |step| step[:key] }
  end

  it "keeps the booker as the customer, because they are the one who pays" do
    expect(order.customer).to eq(booker)
  end

  it "rings the RECIPIENT at every step the courier speaks to somebody" do
    expect(steps["go_to_customer"][:phone]).to eq("+93700000222")
    expect(steps["collect_and_deliver"][:phone]).to eq("+93700000222")
  end

  it "never gives the courier the booker's number" do
    numbers = steps.values.map { |step| step[:phone] }.compact

    expect(numbers).to be_present, "no phone on any step — the check below is vacuous"
    expect(numbers).not_to include(booker.phone)
  end

  it "sends the courier to the recipient's gate, with the recipient's landmark" do
    expect(steps["go_to_customer"][:location]).to eq(latitude: 34.51, longitude: 69.19)
    expect(steps["go_to_customer"][:landmark_note]).to eq("شین دروازه، کوچه سوم، دروازه آبی")
  end

  # The snapshot rule: the booker editing their own profile afterwards must not
  # rewrite where a courier is going.
  it "does not follow the booker when they change their own number" do
    order
    booker.update!(phone: "+93700000999")

    expect(steps["go_to_customer"][:phone]).to eq("+93700000222")
  end

  # Defaulting to the account's phone is right when nobody says otherwise —
  # most orders are for the person ordering.
  it "falls back to the booker's own number when no other is given" do
    own = Orders::PlaceService.new(
      customer: booker, merchant: merchant,
      lines: [ { catalog_item_id: kabab.id, quantity: 1 } ],
      delivery_latitude: 34.5100, delivery_longitude: 69.1900
    ).call

    expect(own.customer_phone).to eq(booker.phone)
  end

  describe "a ride booked for somebody else" do
    let(:trip) do
      create(:trip, passenger: booker, passenger_phone: "+93700000333",
                    pickup_landmark_note: "نزدیک مسجد")
    end

    it "rings the passenger, not the person who booked it" do
      steps = Couriers::JobSteps.new(trip).call

      phones = steps.map { |step| step[:phone] }.compact
      # `all` passes on an EMPTY array, so it is not the positive it looks like.
      expect(phones).to be_present, "no phones at all — both checks below are vacuous"
      expect(phones).to all(eq("+93700000333"))
      expect(phones).not_to include(booker.phone)
    end
  end
end
