module Notifications
  # "YOUR ORDER DID NOT HAPPEN, AND HERE IS WHY." To the customer, for an
  # ending they did not cause (karwan-42 found there was none, 25 Sept 2026).
  #
  # One key pair per KIND of ending (rejected, cancelled, failed), and the
  # REASON as a code in the data, so the app can say the next step rather than
  # only that something failed. The urgent one is `no_answer` ("the shop did
  # not answer; try another"), two minutes after placing. The cruellest is a
  # cancellation long after the screen said "preparing".
  #
  # KEYS and identifiers only, like every push (the allowlist gate): no
  # merchant name, no amounts, no courier.
  class CustomerOrderEnded
    # Literal, not interpolated: push_keys_are_published_spec finds keys by
    # scanning for them, and an interpolated key would be invisible to it.
    KEYS = {
      "rejected" => %w[customer.order_rejected.title customer.order_rejected.body],
      "cancelled" => %w[customer.order_cancelled.title customer.order_cancelled.body],
      "failed" => %w[customer.order_failed.title customer.order_failed.body]
    }.freeze

    def self.applies_to?(order) = KEYS.key?(order.status)

    def initialize(order, client: nil)
      @order = order
      @client = client || FcmClient.new
    end

    def deliver!
      return nil unless self.class.applies_to?(@order) && @order.customer

      ending = @order.status
      tokens = @order.customer.device_tokens.active.pluck(:token)
      result = @client.send_to(
        tokens,
        title_key: KEYS.fetch(ending).first, body_key: KEYS.fetch(ending).last,
        data: {
          kind: Order::JOB_KIND, order_id: @order.id, code: @order.code, ended: ending,
          reason: reason_for(ending),
          deep_link: "karwan://open/order-ended/#{Order::JOB_KIND}/#{@order.id}"
        }
      )

      AuditLog.record!(
        action: "customer.told_order_ended", target: @order,
        details: { channel: "push", status: result.status.to_s, devices: tokens.size,
                   delivered: result.delivered, ended: ending, reached: result.any_delivered? }
      )
      result
    end

    private

    def reason_for(ending)
      { "rejected" => @order.rejection_reason, "cancelled" => @order.cancellation_reason,
        "failed" => @order.failure_reason }[ending].to_s.presence
    end
  end
end
