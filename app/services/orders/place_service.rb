module Orders
  # Turns a cart into an order.
  #
  # This is the one place a delivery comes into existence, and it is
  # deliberately strict, because everything downstream trusts it: dispatch
  # trusts the money, the courier trusts the address, and the customer is told a
  # total at the door that has to match what they agreed.
  #
  # THE SERVER PRICES THE ORDER. Nothing in the payload is trusted to carry an
  # amount — the client sends what was chosen, never what it costs. A client
  # that can name its own price is a client that will.
  #
  # Every line is a SNAPSHOT: item name, unit price, option names and their
  # deltas, all copied at order time. A merchant editing its catalog tomorrow
  # must not rewrite what somebody ordered today (one-way door #1).
  class PlaceService
    Error = Class.new(StandardError)
    MerchantUnavailable = Class.new(Error)
    ItemUnavailable = Class.new(Error)
    InvalidOptions = Class.new(Error)
    EmptyCart = Class.new(Error)
    # NOBODY ON THE PLATFORM OWNS A VEHICLE THAT COULD CARRY THIS. A permanent
    # fact, so refusing here is honest: the alternative is an order that sits
    # undispatched until it times out, and a customer who waited twenty minutes
    # to be told no. "No vehicle available for this item" BEFORE they commit is
    # the kinder answer.
    #
    # Deliberately NOT raised when a suitable vehicle merely happens to be
    # offline — that is a five-minute problem, and refusing it would turn a
    # delivery we could have had into a customer who leaves. See
    # `Dispatch::FleetCapability` for the two questions and why only one of them
    # is a refusal.
    NoVehicleForOrder = Class.new(Error)

    # `lines` is an array of:
    #   { catalog_item_id:, quantity:, option_value_ids: [], notes: }
    def initialize(customer:, merchant:, lines:, delivery_latitude:, delivery_longitude:,
                   delivery_landmark_note: nil, customer_phone: nil, notes: nil,
                   service_tier: :normal)
      @customer = customer
      @merchant = merchant
      @lines = Array(lines)
      @delivery_latitude = delivery_latitude
      @delivery_longitude = delivery_longitude
      @delivery_landmark_note = delivery_landmark_note
      # Falls back to the account's phone, but stays overridable: people order
      # for a relative, and the courier must ring whoever is at the door.
      @customer_phone = customer_phone.presence || customer.phone
      @notes = notes
      # THE CONSENT, and the reason this column shipped before batching did:
      # nobody can ask a past customer whether their completed order could have
      # been shared.
      @service_tier = service_tier.presence || :normal
    end

    def call
      raise MerchantUnavailable, "#{@merchant.name} is not accepting orders" unless @merchant.accepting_orders?

      resolver = CartResolver.new(merchant: @merchant, lines: @lines)
      resolved = resolver.resolve
      items_total = resolver.items_total(resolved)
      required_size = required_size_class(resolved)

      unless Dispatch::FleetCapability.new(required_size).any_vehicle?
        raise NoVehicleForOrder, "nothing in the fleet can carry this order"
      end

      quote = price(items_total)

      Order.transaction do
        order = build_order(quote, required_size)
        resolved.each { |line| persist_line(order, line) }
        # Re-read the total from what was actually written, rather than trusting
        # the figure computed a moment ago. If the two ever disagree, the
        # validation below refuses the order instead of shipping a total nobody
        # can explain.
        order.save!
        record_placement(order)
        # A missed "new order" alert is a lost order. Enqueued inside the
        # transaction so it cannot fire for an order that failed to save;
        # ActiveJob delivers after commit.
        Notifications::MerchantOrderAlertJob.perform_later(order.id)
        order
      end
    end

    private

    def price(items_total)
      Pricing::DeliveryQuote.new(
        merchant: @merchant, items_total: items_total,
        delivery_latitude: @delivery_latitude, delivery_longitude: @delivery_longitude,
        service_tier: @service_tier
      ).call
    end

    # THE SNAPSHOT: the largest thing in the basket decides the vehicle, resolved
    # here and frozen on the row. A merchant re-classifying an item next month
    # must not change what last month's order needed (one-way door #1) — and
    # dispatch must not have to re-derive it from a live catalog on every offer.
    def required_size_class(resolved)
      resolved.map { |line| line[:item].size_class }
              .max_by { |size| SizeClasses.rank(size) } || "small"
    end

    def build_order(quote, required_size)
      Order.new(
        quote.to_attributes.merge(
          # Frozen onto the row, and merged HERE rather than inside
          # `to_attributes` because that shape is shared with `Trip`, which has
          # no such column. A shortage applies to deliveries today.
          shortage_multiplier: quote.shortage_multiplier,
          shortage_multiplier_requested: quote.shortage_multiplier_requested,
          required_size_class: required_size,
          service_tier: @service_tier,
          customer: @customer,
          merchant: @merchant,
          payment_method: :cash,
          status: :placed,
          payment_status: :pending,
          # The address is COPIED, not referenced. The customer edits and
          # deletes their saved pins, and a past order must still say where it
          # actually went.
          delivery_latitude: @delivery_latitude,
          delivery_longitude: @delivery_longitude,
          delivery_landmark_note: @delivery_landmark_note,
          customer_phone: @customer_phone,
          notes: @notes,
          placed_at: Time.current
        )
      )
    end

    def persist_line(order, line)
      item = order.order_items.build(
        catalog_item: line[:item],
        name: line[:item].name,
        unit_price: line[:item].price,
        options_total: line[:options_total],
        quantity: line[:quantity],
        line_total: line[:line_total],
        currency: line[:item].currency,
        notes: line[:notes]
      )

      line[:values].each do |value|
        item.selected_options.build(
          # The SNAPSHOT — what was bought and for how much, as text and
          # numbers. One-way door #1: never a live join.
          option_name: value.catalog_item_option.name,
          value_name: value.name,
          price_delta: value.price_delta,
          currency: value.currency,
          # And the link, used only to rebuild a cart from this order later.
          catalog_item_option_value: value
        )
      end
    end

    # The first row in the order's history. Written by the customer, so the
    # actor is them — `placed` is the only transition nobody else can make.
    def record_placement(order)
      order.transitions.create!(
        from_status: nil, to_status: order.status,
        actor: @customer, actor_role: :customer, created_at: order.placed_at
      )
    end
  end
end
