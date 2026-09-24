require "rails_helper"

# ── TWO MOVES OF ONE JOB, AT THE SAME MOMENT ────────────────────────────────
#
# A shop's tablet on a bad connection: accept is pressed, nothing seems to
# happen, it is pressed again — or the app retries — and both requests arrive
# together, each holding a copy of the order at `placed`.
#
# Reproduced 2026-09-24 through exactly what the merchant controller does
# (`transition_to!`, then `Dispatch::OfferService`): TWO `accepted` rows in the
# transition log, and the second request died on the offers' unique
# (job, sequence) index — a 500 on the tablet for an order that had in fact
# been accepted. That index is also the only reason a second courier was not
# sent. The courier's "delivered" had the same shape until 3c731d3.
#
# Every caller of `transition_to!` shares the fix — merchant accept, preparing,
# ready and reject, the customer's cancel, the courier's problem report, the
# console — so it is tested here, on the method, once.
#
# Real threads on a committed database, with a gate that holds both requests
# just past the in-memory status check until the other arrives (or a second
# passes) — the window the lock has to close.
RSpec.describe "two moves of one job at once", type: :model do
  self.use_transactional_tests = false
  after { DatabaseCleaner.clean_with(:truncation) }

  let(:merchant) { create(:merchant, latitude: 34.5553, longitude: 69.2075) }
  let(:order) do
    create(:order, :with_items, merchant: merchant, customer_total: 500, commission: 50,
                                courier_fee: 100, merchant_payout: 350)
  end

  before do
    courier = create(:user, :courier)
    courier.courier_profile.update!(is_available: true, accepted_job_kinds: %w[delivery ride],
                                    last_latitude: 34.5553, last_longitude: 69.2075,
                                    location_updated_at: Time.current)
    courier.courier_wallet.update!(balance: 5_000, credit_line: 500)
  end

  def hold_both_past_the_status_check
    arrived = Queue.new
    gate = Module.new do
      define_method(:can_transition_to?) do |*args, **kwargs|
        allowed = super(*args, **kwargs)
        if Thread.current[:two_moves_gate]
          arrived << 1
          deadline = Time.current + 1
          sleep 0.01 until arrived.size >= 2 || Time.current > deadline
        end
        allowed
      end
    end
    Order.prepend(gate)
  end

  # What `Api::V1::Merchants::OrdersController#transition!` does for accept.
  def two_accepts_at_once
    2.times.map do
      Thread.new do
        Thread.current[:two_moves_gate] = true
        ActiveRecord::Base.connection_pool.with_connection do
          job = Order.find(order.id)
          next :refused unless job.transition_to!(:accepted, actor: merchant.owner, actor_role: :merchant_owner)

          Dispatch::OfferService.new(job).call ? :offered : :no_offer
        rescue StandardError => e
          e.class
        end
      end
    end.map(&:value)
  end

  it "accepts once, and refuses the other like any stale client" do
    hold_both_past_the_status_check

    outcomes = two_accepts_at_once

    expect(outcomes).to contain_exactly(:offered, :refused)
    expect(order.transitions.where(to_status: "accepted").count).to eq(1)
  end

  # Green with the lock removed too: the offers' unique (job, sequence) index
  # is what holds this, and the second request's 500 was its price. Kept as
  # the guard on THAT — dropping the index would send two couriers to one
  # shop — not as proof of the lock, which the example above is.
  it "offers the job to one courier" do
    hold_both_past_the_status_check

    two_accepts_at_once

    expect(order.offers.count).to eq(1)
  end
end
