require "rails_helper"

# ═══ REVOCATION IS THE MIRROR, AND IT WAS HALF BUILT ═══════════════════════
#
# `IDENTITY_AND_ROLES.md` §3: *"Revocation is the mirror and is easy to forget.
# Unassigning a merchant's owner must revoke `merchant_owner`... **Rejecting or
# suspending a courier must stop dispatch considering them.**"*
#
# Rejecting was handled — `verification_approved?` — and suspending was not.
#
# ── WHY "HE CANNOT ACCEPT ANYWAY" IS NOT AN ANSWER ────────────────────────
#
# `Authenticatable` refuses a suspended account's token, so he cannot take the
# job. He was still the nearest CANDIDATE: the offer sat until
# `dispatch_offer_ttl_sec` expired and the customer waited that long for
# nothing. With `dispatch_max_offers` capped, two suspended couriers in one
# neighbourhood can exhaust the budget and send an order to manual assignment
# that should have dispatched itself.
RSpec.describe "a suspended courier leaves the dispatch pool" do
  let(:merchant) { create(:merchant, latitude: 34.5553, longitude: 69.2075) }
  let(:order) { create(:order, :with_items, :accepted, merchant: merchant) }

  def dispatchable_courier
    courier = create(:user, :courier)
    courier.courier_profile.update!(is_available: true, last_latitude: 34.5553,
                                    last_longitude: 69.2075, location_updated_at: Time.current)
    courier
  end

  it "is not in the candidate scope once the account is suspended" do
    courier = dispatchable_courier
    expect(CourierProfile.dispatchable_for("delivery")).to include(courier.courier_profile),
                                                          "plant a dispatchable courier, or this proves nothing"

    courier.update!(status: :suspended)

    expect(CourierProfile.dispatchable_for("delivery")).not_to include(courier.courier_profile)
  end

  it "is refused by Eligibility, with a reason that names why" do
    courier = dispatchable_courier
    courier.update!(status: :suspended)

    eligibility = Dispatch::Eligibility.new(courier: courier, job: order)

    expect(eligibility).not_to be_eligible
    expect(eligibility.reason).to eq(:account_suspended)
  end

  # ── ASKED FIRST, AND THAT ORDER IS THE POINT ─────────────────────────────
  #
  # A suspended courier who is ALSO off shift must be told the suspension. The
  # other reason is true and useless: he would go on shift and still get
  # nothing, which is the same wasted trip the courier's own screen exists to
  # prevent.
  it "names the suspension ahead of any other reason that is also true" do
    courier = dispatchable_courier
    courier.courier_profile.update!(is_available: false, location_updated_at: 2.hours.ago)
    courier.update!(status: :suspended)

    expect(Dispatch::Eligibility.new(courier: courier, job: order).reason).to eq(:account_suspended)
    expect(Dispatch::CourierReadiness.new(courier).blocked_by).to eq(:account_suspended)
  end

  # ── THE INPUT THAT ACTUALLY SEPARATES THE TWO ORDERINGS ──────────────────
  #
  # The example above cannot tell first from third: its courier is APPROVED, so
  # the checks `account_suspended` would sit behind all pass and the answer is
  # the same either way. Moving it down in `Eligibility` left it green.
  #
  # A suspended courier whose profile is ALSO unapproved is the discriminating
  # case — first gives `account_suspended`, third gives `not_approved` — and it
  # is the realistic one: an operator who suspends an account is often
  # suspending somebody who was never fully approved.
  it "names the suspension even when an earlier-listed reason is also true" do
    courier = dispatchable_courier
    courier.courier_profile.update!(verification_status: :pending)
    courier.update!(status: :suspended)

    told = Dispatch::CourierReadiness.new(courier).blocked_by
    dispatched = Dispatch::Eligibility.new(courier: courier, job: order).reason

    expect(told).to eq(:account_suspended)
    expect(dispatched).to eq(told),
                          "dispatch skips him for #{dispatched.inspect} and he is told #{told.inspect} — " \
                          "the two orderings have come apart"
  end

  # The offer path, which is what the customer actually waits on.
  it "is never offered the job" do
    suspended = dispatchable_courier
    suspended.update!(status: :suspended)

    expect { Dispatch::OfferService.new(order).call }.not_to change { order.offers.count }
  end

  it "still offers the job to an active courier beside him" do
    suspended = dispatchable_courier
    suspended.update!(status: :suspended)
    active = dispatchable_courier

    Dispatch::OfferService.new(order).call

    expect(order.offers.pluck(:courier_id)).to eq([ active.id ]),
                                               "the suspension took the whole pool with it"
  end

  # Reinstating must put him back — a revocation that cannot be undone is a
  # different defect, and `admin/users#reinstate` exists for exactly this.
  it "returns to the pool when the account is reinstated" do
    courier = dispatchable_courier
    courier.update!(status: :suspended)
    courier.update!(status: :active)

    expect(CourierProfile.dispatchable_for("delivery")).to include(courier.courier_profile)
    expect(Dispatch::Eligibility.new(courier: courier, job: order)).to be_eligible
  end
end
