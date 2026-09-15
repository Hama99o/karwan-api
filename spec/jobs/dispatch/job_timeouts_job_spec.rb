require "rails_helper"

RSpec.describe Dispatch::JobTimeoutsJob do
  # The line this job draws: whether anyone is out of pocket yet. Nothing
  # committed means a machine may close it and tell the customer. Food cooked,
  # a courier en route, or cash moved means a human decides.
  describe "states nothing has been committed in — closed automatically" do
    it "rejects an order the merchant never answered" do
      order = create(:order, :overdue)

      result = described_class.new.perform

      expect(order.reload.status).to eq("rejected")
      expect(order.rejection_reason).to eq("closing")
      expect(result[:closed]).to eq(1)
    end

    # Actor nil = the system. That is the difference between "the merchant
    # rejected it" and "the merchant never answered", and support needs both.
    it "records the close as a system action, not a person's" do
      order = create(:order, :overdue)

      described_class.new.perform

      transition = order.reload.transitions.last
      expect(transition).to be_system
      expect(transition.to_status).to eq("rejected")
      expect(transition.reason).to match(/timed out/)
    end

    it "leaves an audit row explaining itself" do
      order = create(:order, :overdue)

      described_class.new.perform

      log = AuditLog.where(action: "order.timed_out", target: order).last
      expect(log).to be_present
      expect(log.after["status"]).to eq("rejected")
    end

    it "cancels a ride nobody accepted" do
      ride = create(:trip, :overdue)

      described_class.new.perform

      expect(ride.reload.status).to eq("cancelled")
      expect(ride.cancellation_reason).to eq("no_courier_available")
    end
  end

  describe "states where money or goods are committed — flagged, never closed" do
    it "does not cancel an order already being prepared" do
      order = create(:order, :preparing)
      order.update_columns(preparing_at: 3.hours.ago, updated_at: 3.hours.ago)

      result = described_class.new.perform

      expect(order.reload.status).to eq("preparing")
      expect(result[:flagged]).to eq(1)
    end

    it "flags it for a human with how long it has been stuck" do
      order = create(:order, :preparing)
      order.update_columns(preparing_at: 3.hours.ago, updated_at: 3.hours.ago)

      described_class.new.perform

      log = AuditLog.where(action: "order.overdue", target: order).last
      expect(log).to be_present
      expect(log.details["status"]).to eq("preparing")
      expect(log.details["minutes_in_state"]).to be >= 175
      expect(log.details["note"]).to match(/needs a human/)
    end

    it "does not cancel a ride already under way" do
      ride = create(:trip, :in_progress)
      ride.update_columns(in_progress_at: 5.hours.ago, updated_at: 5.hours.ago)

      described_class.new.perform

      expect(ride.reload.status).to eq("in_progress")
    end

    it "does not touch a courier's cash by cancelling a picked-up order" do
      order = create(:order, :picked_up)
      order.update_columns(picked_up_at: 5.hours.ago, updated_at: 5.hours.ago)

      described_class.new.perform

      expect(order.reload.status).to eq("picked_up")
    end
  end

  describe "what it leaves alone" do
    it "ignores a job still within its timeout" do
      order = create(:order)

      expect(described_class.new.perform).to eq({ closed: 0, flagged: 0 })
      expect(order.reload.status).to eq("placed")
    end

    # A delivered order is finished, not late. Closing or flagging it would
    # bury the jobs that actually need attention.
    it "ignores terminal jobs however old" do
      order = create(:order, :delivered)
      order.update_columns(created_at: 5.days.ago, updated_at: 5.days.ago)

      expect(described_class.new.perform).to eq({ closed: 0, flagged: 0 })
      expect(order.reload.status).to eq("delivered")
    end

    it "does nothing, and does not raise, on an empty database" do
      expect { described_class.new.perform }.not_to raise_error
    end
  end

  describe "both demand types in one run" do
    it "handles orders and rides together" do
      create(:order, :overdue)
      create(:trip, :overdue)

      expect(described_class.new.perform[:closed]).to eq(2)
    end
  end

  it "is idempotent — a closed job is not closed again" do
    create(:order, :overdue)

    described_class.new.perform

    expect(described_class.new.perform).to eq({ closed: 0, flagged: 0 })
  end
end
