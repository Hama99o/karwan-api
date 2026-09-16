require "rails_helper"

# THE SECOND FREEZE POINT.
#
# Every other amount on an order freezes at the quote. The courier fee cannot:
# it depends on the vehicle, and nobody knows who will accept until they do. So
# it freezes at ASSIGNMENT, with the vehicle that earned it on the row.
#
# Correction 13's purpose survives and only its wording needed amending — the
# customer-facing total never moves, and the payout stays explainable. The
# consequence, which belongs in the admin copy: the platform's margin on a
# delivery is not known until a courier accepts, so those figures are MARGIN
# SO FAR.
RSpec.describe "the courier's pay freezes at assignment", type: :model do
  let(:merchant) { create(:merchant, latitude: 34.5553, longitude: 69.2075) }

  def courier_on(vehicle)
    user = create(:user, :courier)
    user.courier_profile.update!(vehicle_type: vehicle)
    user
  end

  def order_priced_over(km)
    create(:order, :ready, merchant: merchant, distance_km: km)
  end

  before { PricingRate.seed_defaults! }

  it "pays the courier rate for the vehicle that took the job" do
    PricingRate.find_by!(job_kind: "delivery", audience: :courier, vehicle_type: :zarang)
               .update!(base: 500, per_km: 0, minimum: 0)
    order = order_priced_over(4)

    order.update!(courier: courier_on(:zarang))

    expect(order.reload.courier_fee).to eq(500)
  end

  it "records WHICH vehicle earned it, so the payout can be explained later" do
    order = order_priced_over(4)

    order.update!(courier: courier_on(:rishka))

    expect(order.reload.courier_vehicle_type).to eq("rishka")
  end

  # A bicycle and a zarang on the same route are worth different amounts to us
  # — that is the whole point of the courier-side rate.
  it "pays two vehicles differently for the same route" do
    PricingRate.find_by!(job_kind: "delivery", audience: :courier, vehicle_type: :bicycle)
               .update!(base: 10, per_km: 1, minimum: 0)
    PricingRate.find_by!(job_kind: "delivery", audience: :courier, vehicle_type: :zarang)
               .update!(base: 200, per_km: 30, minimum: 0)

    cheap = order_priced_over(4).tap { |o| o.update!(courier: courier_on(:bicycle)) }
    dear = order_priced_over(4).tap { |o| o.update!(courier: courier_on(:zarang)) }

    expect(cheap.reload.courier_fee).to eq(14)
    expect(dear.reload.courier_fee).to eq(320)
  end

  # ── THE SNAPSHOT RULE FROM docs/TESTING.md ─────────────────────────────────
  #
  # A test that the fee is WRITTEN correctly is not a test that it is FROZEN.
  # So: assign, then change the rate underneath, and assert the fee does not
  # move. Without this, a rate edit tonight would silently restate what every
  # courier earned today.
  it "does not move when the rate changes afterwards" do
    order = order_priced_over(4)
    order.update!(courier: courier_on(:motorbike))
    frozen = order.reload.courier_fee

    PricingRate.find_by!(job_kind: "delivery", audience: :courier, vehicle_type: :motorbike)
               .update!(base: 9_999)

    expect(order.reload.courier_fee).to eq(frozen)
  end

  # THE CUSTOMER'S TOTAL IS UNTOUCHED, which is the half correction 13 protects.
  it "never changes what the customer was told" do
    order = order_priced_over(4)

    expect { order.update!(courier: courier_on(:zarang)) }
      .not_to change { order.reload.customer_total }
  end

  # `commission` does NOT move: it is the merchant's rate on the items total
  # and has nothing to do with the vehicle. Nor does the payout the courier
  # hands over at the counter.
  it "leaves the merchant payout and the commission alone" do
    order = order_priced_over(4)
    before = order.slice(:merchant_payout, :commission)

    order.update!(courier: courier_on(:zarang))

    expect(order.reload.slice(:merchant_payout, :commission)).to eq(before)
  end

  # Admin reassignment is a courier assignment too, which is why the freeze is
  # a model callback rather than something the accept endpoint does.
  it "re-freezes when admin reassigns the job to a different vehicle" do
    PricingRate.find_by!(job_kind: "delivery", audience: :courier, vehicle_type: :zarang)
               .update!(base: 777, per_km: 0, minimum: 0)
    order = order_priced_over(4)
    order.update!(courier: courier_on(:motorbike))

    order.update!(courier: courier_on(:zarang))

    expect(order.reload.courier_fee).to eq(777)
    expect(order.reload.courier_vehicle_type).to eq("zarang")
  end

  it "keeps the last payout on the row when the courier is unassigned" do
    order = order_priced_over(4)
    order.update!(courier: courier_on(:rishka))
    fee = order.reload.courier_fee

    order.update!(courier: nil)

    expect(order.reload.courier_fee).to eq(fee)
    expect(order.reload.courier_vehicle_type).to eq("rishka")
  end

  # A fixture or an import with no route keeps the fee it was given: re-pricing
  # on a distance of zero would quietly replace a real figure with a floor.
  it "leaves an order with no distance exactly as it was" do
    order = create(:order, :ready, merchant: merchant, distance_km: nil, courier_fee: 137)

    order.update!(courier: courier_on(:motorbike))

    expect(order.reload.courier_fee).to eq(137)
  end

  it "does not touch the fee when some other field is saved" do
    order = order_priced_over(4)
    order.update!(courier: courier_on(:motorbike))
    fee = order.reload.courier_fee
    PricingRate.find_by!(job_kind: "delivery", audience: :courier, vehicle_type: :motorbike)
               .update!(base: 4_242)

    order.update!(notes: "leave it at the gate")

    expect(order.reload.courier_fee).to eq(fee)
  end
end
