require "rails_helper"

# ── A COURIER DECLINES IN THE SAME SECOND THE SWEEP EXPIRES HIS OFFER ────────
#
# Both paths write the same offer (`respond!`) and both re-run dispatch for
# the job. Suspected on 2026-09-24 while closing the two-offers race; this is
# the record of what actually happens, so it is not re-suspected.
#
# SAFE, AND NOT ONLY BECAUSE OF THE JOB LOCK. Both paths WRITE THE OFFER ROW
# BEFORE re-dispatching — the decline controller responds and then offers;
# `ExpireOffersJob` responds inside its transaction and then offers — and that
# write's row lock serialises them. If the decline commits first the sweep no
# longer finds an expired offer; if the sweep holds the row, the decline waits
# and then finds the sweep's new offer live. These examples stay green with
# `OfferService`'s job lock removed. What turns them red is the sweep
# re-dispatching BEFORE it writes the offer, with the lock removed: two live
# offers. So the ordering is load-bearing, and the lock is the second guard.
# Two re-dispatches that do not share an offer row are
# `two_offers_at_once_spec.rb`.
#
# What is NOT protected, and is cosmetic: on the overlap the offer's final
# status is whichever write landed last (`declined` or `timed_out`), so
# `Couriers::Reliability` can file one event in a thousand in the other column
# (docs/NOTES.md).
#
# Real threads on a committed database, the two real paths — what
# `couriers/offers#decline` does, and `Dispatch::ExpireOffersJob` — held
# together just past "is there a live offer?" until the other arrives.
RSpec.describe "a decline racing the expiry sweep" do
  self.use_transactional_tests = false
  after { DatabaseCleaner.clean_with(:truncation) }

  let(:merchant) { create(:merchant, latitude: 34.5553, longitude: 69.2075) }
  let!(:order) do
    create(:order, :with_items, :accepted, merchant: merchant, customer_total: 500, commission: 50,
                                           courier_fee: 100, merchant_payout: 350)
  end

  def courier_nearby(offset)
    create(:user, :courier).tap do |courier|
      courier.courier_profile.update!(is_available: true, accepted_job_kinds: %w[delivery ride],
                                      last_latitude: 34.5553 + offset, last_longitude: 69.2075,
                                      location_updated_at: Time.current)
      courier.courier_wallet.update!(balance: 5_000, credit_line: 500)
    end
  end

  let!(:first) { courier_nearby(0.0) }
  let!(:others) { [ courier_nearby(0.001), courier_nearby(0.002) ] }
  # Offered, and past its deadline: the sweep will take it, and the courier is
  # tapping "no" at the same moment.
  let!(:offer) do
    create(:offer, courier: first, offerable: order, sequence: 1, status: :offered,
                   offered_at: 70.seconds.ago, expires_at: 1.second.ago)
  end

  # One path must be caught between "is there a live offer?" and its insert
  # while the other runs to the end — the ordering that made two live offers
  # before 95bf342. Holding both together instead only reaches the milder
  # case (both read the same sequence, the unique index refuses one, the sweep
  # logs it), and an earlier version of this spec did exactly that and stayed
  # green with the lock removed.
  def race(waiting:)
    finished = Queue.new
    gate = Module.new do
      define_method(:pending_offer?) do
        live = super()
        finished.pop(timeout: 1) if Thread.current[:race] == waiting
        live
      end
    end
    Dispatch::OfferService.prepend(gate)

    run = lambda do |role, &work|
      Thread.new do
        Thread.current[:race] = role
        ActiveRecord::Base.connection_pool.with_connection { work.call }
      rescue StandardError => e
        e
      ensure
        finished << :done unless role == waiting
      end
    end

    decline = lambda do
      mine = Offer.find(offer.id)
      mine.respond!(:declined)
      Dispatch::OfferService.new(mine.offerable).call
    end
    sweep = -> { Dispatch::ExpireOffersJob.perform_now }

    held = run.call(waiting) { waiting == :decline ? decline.call : sweep.call }
    sleep 0.2 # the held path is inside the window before the other starts
    other_role = waiting == :decline ? :sweep : :decline
    other = run.call(other_role) { other_role == :decline ? decline.call : sweep.call }
    [ held, other ].map(&:value)
  end

  %i[decline sweep].each do |waiting|
    it "leaves one live offer when the #{waiting} is the one caught in the window" do
      results = race(waiting: waiting)

      expect(results.grep(StandardError)).to be_empty
      expect(order.offers.pending.count).to eq(1)
      expect(order.offers.pending.pluck(:courier_id)).not_to include(first.id)
    end
  end
end
