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

      resolver = CartResolver.new(merchant: @merchant, lines: @lines)
      # Resolved ONCE and carried, rather than resolved for the total and
      # thrown away. The per-line figures were computed here all along and
      # discarded, so the app had nothing server-computed to show per line —
      # which left it summing catalog prices on the device. CLAUDE.md is
      # explicit that a total is never computed on the client, and edu-safi
      # shipped that failure three times.
      resolved = resolver.resolve

      quote = Pricing::DeliveryQuote.new(
        merchant: @merchant, items_total: resolver.items_total(resolved),
        delivery_latitude: @delivery_latitude, delivery_longitude: @delivery_longitude
      ).call

      quote.with(lines: resolved, dispatch_warning: dispatch_warning(resolved))
    end

    private

    # Asked at QUOTE time, not at placement, because this is a decision the
    # customer makes and they can only make it before they commit. Recomputed
    # on every quote rather than frozen: a zarang coming online five minutes
    # later should make the warning disappear, and it will.
    #
    # Costs no query for food, which is every order today — everything carries
    # `small`.
    def dispatch_warning(resolved)
      required = resolved.map { |line| line[:item].size_class }
                         .max_by { |size| SizeClasses.rank(size) } || "small"

      return nil if Dispatch::FleetCapability.new(required).any_available?

      "no_vehicle_online"
    end
  end
end
