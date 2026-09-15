module Orders
  # Prices a cart without creating anything.
  #
  # Shares its line resolution with PlaceService rather than reimplementing it,
  # because the whole point is that the quoted price and the charged price are
  # the same number. Two code paths would drift, and the customer would be
  # asked for a different total at the door than the one they agreed to.
  class QuoteService
    def initialize(merchant:, lines:, delivery_latitude:, delivery_longitude:)
      @merchant = merchant
      @lines = Array(lines)
      @delivery_latitude = delivery_latitude
      @delivery_longitude = delivery_longitude
    end

    def call
      raise PlaceService::MerchantUnavailable, "#{@merchant.name} is not accepting orders" unless @merchant.accepting_orders?

      items_total = CartResolver.new(merchant: @merchant, lines: @lines).items_total

      Pricing::DeliveryQuote.new(
        merchant: @merchant, items_total: items_total,
        delivery_latitude: @delivery_latitude, delivery_longitude: @delivery_longitude
      ).call
    end
  end
end
