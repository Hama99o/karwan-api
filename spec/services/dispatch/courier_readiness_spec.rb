require "rails_helper"

# ── THE COURIER IS TOLD WHY HIS PHONE IS QUIET ─────────────────────────────
#
# `Eligibility` names fourteen reasons a courier is skipped and the courier was
# told none of them. Eight are about him alone and are answerable at any moment;
# six are about a pairing and are not.
RSpec.describe Dispatch::CourierReadiness do
  let(:courier) { create(:user, :courier) }

  # `:courier` already builds an APPROVED profile and a wallet; what it does not
  # do is put the courier on shift with a fresh fix. The factory's own `:available`
  # trait is the right vocabulary for that — my first version set `latitude` by
  # hand and the column is `last_latitude`, which the factory already knew.
  def ready_courier
    courier.courier_profile.update!(is_available: true, last_latitude: 34.5553,
                                    last_longitude: 69.2075, location_updated_at: Time.current)
    courier
  end

  it "says nothing is blocking a courier who is ready" do
    expect(described_class.new(ready_courier).blocked_by).to be_nil
  end

  it "names being off shift" do
    ready_courier.courier_profile.update!(is_available: false)

    expect(described_class.new(courier).blocked_by).to eq(:off_shift)
  end

  it "names an unapproved profile" do
    ready_courier.courier_profile.update!(verification_status: :pending)

    expect(described_class.new(courier).blocked_by).to eq(:not_approved)
  end

  it "names a position too old to dispatch on" do
    ready_courier.courier_profile.update!(location_updated_at: 2.hours.ago)

    expect(described_class.new(courier).blocked_by).to eq(:stale_location)
  end

  it "names a blocked wallet" do
    ready_courier.courier_wallet.update!(balance: -500, credit_line: 500)

    expect(described_class.new(courier).blocked_by).to eq(:wallet_blocked)
  end

  # ANY live job, with none to exclude — the question here is "are you carrying
  # anything", not "does this particular offer conflict".
  it "names already carrying a job, of either demand type" do
    ready_courier
    create(:order, :with_items, :picked_up, courier: courier)

    expect(described_class.new(courier).blocked_by).to eq(:already_on_a_job)
  end

  it "names carrying a ride just the same" do
    ready_courier
    create(:trip, :in_progress, courier: courier)

    expect(described_class.new(courier).blocked_by).to eq(:already_on_a_job)
  end

  # ── ONE VOCABULARY, ASSERTED ─────────────────────────────────────────────
  #
  # A second list of words for one concept is how the server's `merchant_owner`
  # and the app's `merchant` came to exist with no translation between them.
  it "returns only words Eligibility already uses" do
    expect(described_class::ORDER - Dispatch::Eligibility::REASONS.keys).to be_empty
  end

  # ── AND THE HONEST LIMIT, STATED AS AN ASSERTION ─────────────────────────
  #
  # Six reasons are about a PAIRING and this must never claim to answer them.
  # If one is ever added to ORDER, a shift screen starts making a claim it
  # cannot support for a job that does not exist.
  it "does not pretend to answer a reason that needs a job" do
    pairing = %i[wrong_job_kind vehicle_too_small wrong_vehicle_class
                 too_many_passengers too_far insufficient_credit]

    expect(described_class::ORDER & pairing).to be_empty
    expect(pairing - Dispatch::Eligibility::REASONS.keys).to be_empty,
                                                            "this list has drifted from Eligibility's"
    expect(described_class::ORDER.size + pairing.size).to eq(Dispatch::Eligibility::REASONS.size),
                                                         "a reason has been added to Eligibility and belongs in " \
                                                         "exactly one of these two lists — decide which"
  end

  # ── AND THEY MUST AGREE ON WHICH REASON COMES FIRST ──────────────────────
  #
  # THE EXAMPLE BELOW DOES NOT COVER THIS, which planting proved rather than
  # arguing. Each courier it builds has exactly ONE thing wrong, so any ordering
  # gives the same answer — moving `wallet_blocked` above `stale_location` in
  # `CourierReadiness` left it fully green.
  #
  # Order is the whole point of this class: the courier must be told the same
  # FIRST reason the dispatcher would hit, or he fixes the wrong thing. Topping
  # up a wallet when the real problem is a phone that has not reported its
  # position buys nothing, and he has spent money to learn that.
  #
  # So this plants TWO faults at once and demands the same answer from both.
  it "names the same FIRST reason as Eligibility when more than one thing is wrong" do
    [
      # Eligibility meets stale_location before the wallet checks, deliberately:
      # "a distance computed from a position we do not trust is worse than no
      # distance at all".
      { faults: %i[stale_location wallet_blocked], first: :stale_location },
      # And off_shift before everything, because a courier who is not on shift
      # has not asked for work at all.
      { faults: %i[off_shift wallet_blocked], first: :off_shift },
      { faults: %i[off_shift stale_location], first: :off_shift }
    ].each do |scenario|
      fresh = create(:user, :courier)
      profile = fresh.courier_profile
      profile.update!(is_available: true, last_latitude: 34.5553, last_longitude: 69.2075,
                      location_updated_at: Time.current)

      scenario[:faults].each do |fault|
        case fault
        when :off_shift then profile.update!(is_available: false)
        when :stale_location then profile.update!(location_updated_at: 2.hours.ago)
        when :wallet_blocked then fresh.courier_wallet.update!(balance: -500, credit_line: 500)
        end
      end

      job = create(:order, :with_items, merchant: create(:merchant, latitude: 34.5553, longitude: 69.2075))
      told = described_class.new(fresh).blocked_by
      dispatched = Dispatch::Eligibility.new(courier: fresh, job: job).reason

      expect(told).to eq(scenario[:first]),
                      "with #{scenario[:faults].join(' and ')} the courier is told #{told.inspect}"
      expect(dispatched).to eq(told),
                            "dispatch skips him for #{dispatched.inspect} and he is told #{told.inspect} — " \
                            "he will fix the wrong thing"
    end
  end

  # ── THE TWO MUST AGREE, PROVEN RATHER THAN ASSUMED ───────────────────────
  #
  # The checks are written twice, because Eligibility's ordering is load-bearing
  # and interleaves courier and pairing reasons — its comments explain why each
  # sits where it does. Duplication is the cheaper risk, but only if drift is
  # caught, so this runs the real Eligibility against a real job and demands the
  # same answer.
  it "gives the same answer as Eligibility for every courier-only reason" do
    %i[off_shift not_approved stale_location wallet_blocked].each do |expected|
      fresh = create(:user, :courier)
      profile = fresh.courier_profile
      profile.update!(is_available: true, last_latitude: 34.5553, last_longitude: 69.2075,
                      location_updated_at: Time.current)
      wallet = fresh.courier_wallet

      case expected
      when :off_shift then profile.update!(is_available: false)
      when :not_approved then profile.update!(verification_status: :pending)
      when :stale_location then profile.update!(location_updated_at: 2.hours.ago)
      when :wallet_blocked then wallet.update!(balance: -500, credit_line: 500)
      end

      job = create(:order, :with_items, merchant: create(:merchant, latitude: 34.55, longitude: 69.21))

      expect(described_class.new(fresh).blocked_by).to eq(expected)
      expect(Dispatch::Eligibility.new(courier: fresh, job: job).reason).to eq(expected),
                                                                           "Eligibility says " \
                                                                           "#{Dispatch::Eligibility.new(courier: fresh, job: job).reason.inspect} " \
                                                                           "where the courier is told #{expected.inspect}"
    end
  end
end
