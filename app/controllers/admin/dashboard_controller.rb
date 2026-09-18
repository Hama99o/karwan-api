# The ops console landing page.
#
# Not a chart wall. The questions someone actually opens this to answer: what
# needs attention right now, how much have we earned, how many couriers are on
# shift. PRODUCT.md asks for "no charts" on the merchant side and the same
# restraint applies here — numbers that drive a decision, nothing that drives a
# feeling.
module Admin
  class DashboardController < Admin::ApplicationController
    def index
      @live_orders = Order.live.count
      @overdue_orders = Order.live.overdue.count
      @unassigned_orders = Order.live.where(courier_id: nil).count
      @live_trips = Trip.live.count
      @overdue_trips = Trip.live.overdue.count

      @couriers_on_shift = CourierProfile.verification_approved.available.count
      @couriers_pending = CourierProfile.verification_pending.count
      @merchants_open = Merchant.orderable.count
      @merchants_total = Merchant.kept.status_active.count

      # Grouped by currency, never summed across it.
      @commission_today = commission_since(Time.zone.now.beginning_of_day)
      @commission_week = commission_since(7.days.ago)
      # Money couriers are holding on our behalf — our actual exposure.
      @cash_outstanding = outstanding_cash

      # ── WHICH RESTAURANTS NEVER HEARD THEIR ALERT ──────────────────────
      #
      # `Notifications::MerchantAlert` already records
      # `needs_human_contact: true` when a push reached no device — unconfigured
      # FCM, no registered tablet, every token dead. It has recorded it since
      # the day it was written and **nothing read it**: `details` is a show-page
      # field on `AuditLogDashboard`, so answering "who do I need to ring?"
      # meant opening every `merchant.alerted` row and reading its JSON.
      #
      # PRODUCT.md: a missed alert is a lost order, not an annoyance. The three
      # channels are push, in-app polling, and a human — and the human is the
      # one that has to be told. This is that telling.
      @merchants_to_ring = merchants_needing_a_call

      @recent_interventions = AuditLog.interventions.newest_first.limit(10)
    end

    private

    def commission_since(from)
      orders = Order.where(status: :delivered, delivered_at: from..).group(:currency).sum(:commission)
      trips = Trip.where(status: :completed, completed_at: from..).group(:currency).sum(:commission)

      orders.merge(trips) { |_currency, a, b| a + b }
    end

    # Only LIVE orders: an alert that failed on an order since delivered was
    # resolved by somebody, and a number that counts settled history is a
    # number an operator learns to ignore.
    def merchants_needing_a_call
      AuditLog.where(action: "merchant.alerted", target_type: "Order")
              .where("details->>'needs_human_contact' = 'true'")
              .where(target_id: Order.live.select(:id))
              .distinct
              .count(:target_id)
    end

    def outstanding_cash
      orders = Order.where(payment_status: :collected).group(:currency).sum(:commission)
      trips = Trip.where(payment_status: :collected).group(:currency).sum(:commission)

      orders.merge(trips) { |_currency, a, b| a + b }
    end
  end
end
