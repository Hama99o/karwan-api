require "rails_helper"

# ── TWO TAPS THAT ARRIVE TOGETHER ────────────────────────────────────────────
#
# A courier on bad signal taps "delivered", sees nothing, and taps again — or
# the app's own retry fires — and both requests reach the server at once.
#
# Reproduced on 2026-09-24: both requests returned ok and the transition log
# held TWO `delivered` rows. The commission was charged once even then — the
# first request's UPDATE held the order row, so the second one's "already
# charged?" check ran after the first had committed — which is why there is no
# commission example here: it passed with the lock removed, so it proved nothing.
#
# WHY THREADS AND NOT TWO STALE COPIES: `JobSteps` reads the transition log
# fresh, so a copy loaded before the first delivery is refused anyway. The
# window is only open while BOTH requests are between reading the step and
# committing — which is what the gate below holds open. With the row lock the
# second request cannot reach the gate until the first commits, the first
# gives up waiting after a second, and the second then sees `delivered`.
#
# Real commits, so no transactional fixture: each thread has its own
# connection and would not see the other's uncommitted rows.
RSpec.describe Couriers::AdvanceJobService do
  self.use_transactional_tests = false
  after { DatabaseCleaner.clean_with(:truncation) }

  let(:courier) { create(:user, :courier) }
  let(:order) do
    create(:order, :with_items, :picked_up, merchant: create(:merchant), courier: courier,
                                            customer_total: 500, commission: 50,
                                            courier_fee: 100, merchant_payout: 350)
  end

  before do
    courier.courier_wallet.update!(balance: 5_000, credit_line: 500)
    order.transitions.create!(to_status: "picked_up", actor_role: :courier, actor: courier)
  end

  # Holds each request at the step check until the other arrives, or a second.
  def hold_both_at_the_step_check
    arrived = Queue.new
    gate = Module.new do
      define_method(:call) do
        steps = super()
        arrived << 1
        deadline = Time.current + 1
        sleep 0.01 until arrived.size >= 2 || Time.current > deadline
        steps
      end
    end
    allow(Couriers::JobSteps).to receive(:new).and_wrap_original do |original, *args|
      original.call(*args).extend(gate)
    end
  end

  def two_taps_at_once
    2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          described_class.new(job: Order.find(order.id), courier: User.find(courier.id),
                              step_key: "collect_and_deliver").call
          :delivered
        rescue described_class::Error => e
          e.class
        end
      end
    end.map(&:value)
  end

  it "delivers once and refuses the other" do
    hold_both_at_the_step_check

    outcomes = two_taps_at_once

    expect(outcomes).to contain_exactly(:delivered, described_class::NothingToDo)
    expect(order.transitions.where(to_status: "delivered").count).to eq(1)
  end
end
