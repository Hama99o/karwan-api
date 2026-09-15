module Notifications
  # "A new order" reaching a merchant.
  #
  # A MISSED ALERT IS A LOST ORDER, not an annoyance — so this is deliberately
  # ONE OF THREE CHANNELS and never the channel:
  #
  #   1. push, here
  #   2. in-app polling while the app is open — already served by
  #      GET /api/v1/merchant/orders, which is why no second endpoint exists
  #   3. an SMS or telephone path, which is a human step and is FLAGGED rather
  #      than automated: no SMS provider is wired, because that costs money and
  #      is Hamma9900's decision
  #
  # `deliver!` reports what happened so the caller can escalate. Returning
  # "sent" when nothing arrived is the failure mode this class exists to avoid.
  class MerchantAlert
    def initialize(order, client: nil)
      @order = order
      @client = client || FcmClient.new
    end

    def deliver!
      owner = @order.merchant&.owner
      tokens = owner ? owner.device_tokens.active.pluck(:token) : []

      result = @client.send_to(
        tokens,
        title_key: "merchant.alert.new_order.title",
        body_key: "merchant.alert.new_order.body",
        data: {
          order_id: @order.id,
          order_code: @order.code,
          item_count: @order.order_items.sum(&:quantity),
          # The merchant is entitled to know what they are being paid before
          # they accept.
          merchant_payout: @order.merchant_payout,
          currency: @order.currency,
          # So the app can route straight to the order rather than the board.
          deep_link: "karwan://merchant/orders/#{@order.id}"
        }
      )

      record(result, tokens.size)
      result
    end

    private

    # Written down because "did the merchant ever get told" is asked after
    # every lost order, and because a merchant with no registered device is a
    # recruitment problem rather than a bug — it should be visible in the
    # console, not buried in a log.
    def record(result, token_count)
      AuditLog.record!(
        action: "merchant.alerted",
        target: @order,
        details: {
          channel: "push", status: result.status.to_s,
          devices: token_count, delivered: result.delivered, failed: result.failed,
          needs_human_contact: !result.any_delivered?
        }
      )
    end
  end
end
