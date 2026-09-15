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

    # `lines` is an array of:
    #   { catalog_item_id:, quantity:, option_value_ids: [], notes: }
    def initialize(customer:, merchant:, lines:, delivery_latitude:, delivery_longitude:,
                   delivery_landmark_note: nil, customer_phone: nil, notes: nil)
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
    end

    def call
      raise EmptyCart, "an order needs at least one item" if @lines.empty?
      raise MerchantUnavailable, "#{@merchant.name} is not accepting orders" unless @merchant.accepting_orders?

      resolved = @lines.map { |line| resolve_line(line) }
      items_total = resolved.sum { |line| line[:line_total] }
      quote = price(items_total)

      Order.transaction do
        order = build_order(quote)
        resolved.each { |line| persist_line(order, line) }
        # Re-read the total from what was actually written, rather than trusting
        # the figure computed a moment ago. If the two ever disagree, the
        # validation below refuses the order instead of shipping a total nobody
        # can explain.
        order.save!
        record_placement(order)
        order
      end
    end

    private

    def resolve_line(line)
      item = @merchant.catalog_items.kept.find_by(id: line[:catalog_item_id])
      raise ItemUnavailable, "item #{line[:catalog_item_id]} is not on this menu" if item.nil?
      raise ItemUnavailable, "#{item.name} is sold out" unless item.is_available?

      quantity = line[:quantity].to_i
      raise InvalidOptions, "quantity must be at least 1" if quantity < 1

      values = resolve_option_values(item, Array(line[:option_value_ids]))
      options_total = values.sum { |value| value.price_delta }

      {
        item: item,
        quantity: quantity,
        values: values,
        options_total: options_total,
        line_total: ((item.price + options_total) * quantity).round(2),
        notes: line[:notes]
      }
    end

    # Validates the choices against the item's own option rules, per option.
    # The client enforces these too, but a client is a suggestion — a required
    # size missing here is an order the kitchen cannot make.
    def resolve_option_values(item, value_ids)
      values = CatalogItemOptionValue.where(id: value_ids)
                                     .where(catalog_item_option: item.options)
                                     .to_a

      unknown = value_ids.map(&:to_i) - values.map(&:id)
      raise InvalidOptions, "options #{unknown.join(', ')} do not belong to #{item.name}" if unknown.any?

      sold_out = values.reject(&:is_available?)
      raise ItemUnavailable, "#{sold_out.map(&:name).join(', ')} unavailable" if sold_out.any?

      item.options.each { |option| validate_selection(option, values) }

      values
    end

    def validate_selection(option, values)
      chosen = values.count { |value| value.catalog_item_option_id == option.id }
      minimum = option.minimum_required
      maximum = option.maximum_allowed

      raise InvalidOptions, "#{option.name} requires at least #{minimum}" if chosen < minimum
      raise InvalidOptions, "#{option.name} allows at most #{maximum}" if maximum.present? && chosen > maximum
    end

    def price(items_total)
      Pricing::DeliveryQuote.new(
        merchant: @merchant, items_total: items_total,
        delivery_latitude: @delivery_latitude, delivery_longitude: @delivery_longitude
      ).call
    end

    def build_order(quote)
      Order.new(
        quote.to_attributes.merge(
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
          option_name: value.catalog_item_option.name,
          value_name: value.name,
          price_delta: value.price_delta,
          currency: value.currency
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
