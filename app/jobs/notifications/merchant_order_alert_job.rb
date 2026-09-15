module Notifications
  # Loud, repeating, until acknowledged.
  #
  # PRODUCT.md assumes a cheap tablet propped on a counter in a noisy kitchen,
  # so one push is not an alert — it is a hope. This re-sends while the order is
  # still unanswered, then escalates to a human.
  #
  # ACKNOWLEDGEMENT IS THE MERCHANT ACTING, not tapping a dialog: the order
  # leaving `placed` is the only acknowledgement that means anything, because a
  # dismissed notification and a cooked meal are different things.
  class MerchantOrderAlertJob < ApplicationJob
    queue_as :default

    # Five attempts over roughly two minutes, which is the same window as the
    # `placed` timeout — after that the order is closed automatically and
    # ringing a merchant about it would be worse than useless.
    MAX_ATTEMPTS = 5
    INTERVAL = 25.seconds

    def perform(order_id, attempt: 1)
      order = Order.find_by(id: order_id)
      return { stopped: :gone } if order.nil?
      # Acknowledged: they have accepted, rejected, or somebody cancelled.
      return { stopped: :answered, attempts: attempt - 1 } unless order.status == "placed"

      result = MerchantAlert.new(order).deliver!

      if attempt >= MAX_ATTEMPTS
        escalate(order, result)
        return { stopped: :escalated, attempts: attempt }
      end

      self.class.set(wait: INTERVAL).perform_later(order_id, attempt: attempt + 1)
      { sent: true, attempt: attempt }
    end

    private

    # The third channel, and it is a PERSON. Delivery is an operations business
    # with an app attached: when an order goes wrong somebody has to fix it
    # now, in Dari, in Kabul. So this writes the row that puts it in front of
    # them rather than pretending an automated retry will work.
    def escalate(order, result)
      AuditLog.record!(
        action: "merchant.alert_unanswered",
        target: order,
        details: {
          attempts: MAX_ATTEMPTS,
          push_status: result.status.to_s,
          merchant: order.merchant&.name,
          merchant_phone: order.merchant&.phone,
          contact_person: order.merchant&.contact_person_name,
          contact_phone: order.merchant&.contact_person_phone,
          note: "push exhausted — telephone the merchant"
        }
      )
    end
  end
end
