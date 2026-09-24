require "rails_helper"

# ── TWO DISPATCHES OF ONE JOB, AT THE SAME MOMENT ───────────────────────────
#
# Four callers re-run dispatch for a job: the shop's accept, a courier's
# decline, `ExpireOffersJob`, and the console's redispatch. Two of them can
# land together — a courier declines in the same second the sweep expires his
# offer — and `OfferService#call` was check-then-create: "is there a live
# offer?" then "create one".
#
# The interleaving that does the damage, reproduced 2026-09-24: B asks "live
# offer?" and hears no; A creates offer 1 and commits; B reads the highest
# sequence AFTER that, creates offer 2, and the job has TWO LIVE OFFERS — two
# couriers told to go to one shop, one of whom drives there for nothing. (When
# both read the sequence first, the unique (job, sequence) index refuses B
# instead, as a 500 on the courier's decline.)
#
# The gate holds B just after "live offer?" until A has finished, or a second
# passes — without the lock that is the window above; with it, B holds the
# job's row and A waits for B instead.
RSpec.describe "two dispatches of one job at once" do
  self.use_transactional_tests = false
  after { DatabaseCleaner.clean_with(:truncation) }

  let(:merchant) { create(:merchant, latitude: 34.5553, longitude: 69.2075) }
  let!(:order) do
    create(:order, :with_items, :accepted, merchant: merchant, customer_total: 500, commission: 50,
                                           courier_fee: 100, merchant_payout: 350)
  end

  before do
    2.times do |i|
      courier = create(:user, :courier)
      courier.courier_profile.update!(is_available: true, accepted_job_kinds: %w[delivery ride],
                                      last_latitude: 34.5553 + (i * 0.001), last_longitude: 69.2075,
                                      location_updated_at: Time.current)
      courier.courier_wallet.update!(balance: 5_000, credit_line: 500)
    end
  end

  it "leaves one live offer" do
    a_finished = Queue.new
    gate = Module.new do
      define_method(:pending_offer?) do
        pending = super()
        a_finished.pop(timeout: 1) if Thread.current[:dispatch_gate] == :b
        pending
      end
    end
    Dispatch::OfferService.prepend(gate)

    dispatch = lambda do |role|
      Thread.new do
        Thread.current[:dispatch_gate] = role
        ActiveRecord::Base.connection_pool.with_connection do
          Dispatch::OfferService.new(Order.find(order.id)).call
        rescue StandardError => e
          e.class
        ensure
          a_finished << :done if role == :a
        end
      end
    end

    b = dispatch.call(:b)
    sleep 0.2 # B is inside the window before A starts
    a = dispatch.call(:a)
    [ a, b ].each(&:join)

    expect(order.offers.pending.count).to eq(1)
  end
end
