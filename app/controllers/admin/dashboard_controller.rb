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

      # ── CAN A MESSAGE LEAVE THIS BOX AT ALL? ───────────────────────────
      #
      # `bin/preflight` answers this and **only ever runs on a developer's
      # machine**. On the deployed box nothing says the channels are dead, and
      # both fail silently by design: the log adapter writes the code where a
      # developer can read it, and `FcmClient` logs "would notify" and returns
      # `:unconfigured`. Every screen stays green while nothing arrives.
      #
      # What it costs is not symmetric, which is why they are listed separately
      # rather than as one "notifications" light:
      #
      #   SMS dead  — a user who forgot their password and has no email cannot
      #               get back in at all. Correction 2 made email the ADDITIONAL
      #               identifier, so in this market that is most users.
      #   push dead — the merchant alert loses one of its three channels.
      #               PRODUCT.md already refuses to rely on any single one, so
      #               polling still works; it is a degradation, not a lockout.
      @dead_channels = channels_that_cannot_deliver

      # ── DELIVERED, AND NOBODY LOOKED ──────────────────────────────────
      #
      # The tile above counts alerts that reached no device. This counts the
      # ones that arrived and were never acknowledged — a tablet on a counter
      # in a noisy kitchen, an order going cold while the screen flashes at an
      # empty room. It is the worse of the two because nothing in the system
      # looks wrong.
      #
      # Two minutes' grace: an order placed thirty seconds ago is not a
      # problem, it is an order, and a tile that counts it is a tile an
      # operator learns to ignore.
      @unacknowledged_orders = Order.awaiting_acknowledgement.count

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
    # Asked of the adapters themselves rather than of ENV, so this cannot
    # disagree with what the app would actually do when it tries to send.
    # `SmsClient::NON_PRODUCTION` is the same rule `bin/preflight` asks for.
    def channels_that_cannot_deliver
      dead = []
      dead << :sms unless Notifications::SmsClient.production_ready?
      dead << :push unless Notifications::FcmClient.new.configured?
      dead
    end

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
