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

      item_count = @order.order_items.sum(&:quantity)
      result = @client.send_to(
        tokens,
        alarm: true,
        # In WORDS, in the owner's own language, so a closed app still shows
        # it. The only push the server writes — see Notifications::PushCopy.
        display: owner && PushCopy.new_order(locale: owner.locale,
                                             values: { order_code: @order.code, item_count: item_count }),
        title_key: "merchant.alert.new_order.title",
        body_key: "merchant.alert.new_order.body",
        data: {
          order_id: @order.id,
          order_code: @order.code,
          item_count: item_count,
          # The merchant is entitled to know what they are being paid before
          # they accept.
          merchant_payout: @order.merchant_payout,
          currency: @order.currency,
          # WHAT HAPPENED AND TO WHICH RECORD, not a screen path: the app's
          # three role homes are route groups that all sit at "/", so a path
          # from here is ambiguous by construction (the old
          # `karwan://merchant/orders/:id` matched a CUSTOMER's restaurant
          # page). The app decides the screen.
          deep_link: "karwan://open/new-order/#{@order.id}"
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
