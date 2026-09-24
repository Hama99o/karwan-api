module Orders
  # WHAT MAKES TWO "PLACE ORDER" REQUESTS THE SAME REQUEST.
  #
  # An idempotency key on its own means "return what I returned last time",
  # which is wrong the moment the customer, unsure whether his first attempt
  # landed, changes the basket and tries again: he would be shown an order for
  # food he no longer wants. So a repeated key is compared against this, and
  # only an identical request is answered with the existing order.
  #
  # THE RULE FOR WHAT IS IN IT: every field the client SENDS that the server
  # reads — and nothing the server computes. Leave a sent field out and a real
  # change slips through as "the same request"; put a computed one in (a
  # price, a fee) and a menu edit between two attempts makes a genuine retry
  # look like a conflict. The client never sends an amount, so no amount is
  # here.
  #
  # CANONICAL, so a harmless difference is not a conflict: blank and missing
  # are one thing; "34.5553" and "34.555300" are one coordinate (the column's
  # six places); the lines are a basket, so their order does not matter, and
  # neither does the order of a line's options.
  class RequestFingerprint
    def initialize(order_params:, lines:, delivery_address_id:, service_tier:)
      @order_params = order_params
      @lines = lines
      @delivery_address_id = delivery_address_id
      @service_tier = service_tier
    end

    def digest
      Digest::SHA256.hexdigest(JSON.generate(canonical))
    end

    private

    def canonical
      [
        integer(@order_params[:merchant_id]),
        integer(@delivery_address_id),
        coordinate(@order_params[:delivery_latitude]),
        coordinate(@order_params[:delivery_longitude]),
        text(@order_params[:delivery_landmark_note]),
        text(@order_params[:customer_phone]),
        text(@order_params[:notes]),
        text(@service_tier),
        @lines.map { |line| canonical_line(line) }.sort
      ]
    end

    def canonical_line(line)
      [
        integer(line[:catalog_item_id]),
        integer(line[:quantity]),
        text(line[:notes]),
        Array(line[:option_value_ids]).map { |id| integer(id) }.uniq.sort
      ]
    end

    def text(value)
      value.to_s.strip
    end

    def integer(value)
      value.to_s.strip.match?(/\A-?\d+\z/) ? value.to_s.to_i.to_s : text(value)
    end

    def coordinate(value)
      BigDecimal(value.to_s.strip).round(6).to_s("F")
    rescue ArgumentError, TypeError
      text(value)
    end
  end
end
