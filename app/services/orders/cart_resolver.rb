module Orders
  # Turns a cart payload into priced, validated lines.
  #
  # Its own object because BOTH placing an order and quoting one need exactly
  # this, and they must agree: the quoted total and the charged total have to be
  # the same number, or the customer is asked for something different at the
  # door than they agreed to.
  #
  # The first attempt had QuoteService instantiate PlaceService with a nil
  # customer just to borrow this method. That failed immediately — PlaceService
  # needs a customer for the contact number — and the failure was the design
  # telling me it was the wrong shape. Shared logic belongs in a shared object,
  # not in a service instantiated with nils to get at one of its methods.
  #
  # Nothing here trusts a price from the client. The payload says WHAT was
  # chosen; every amount comes from the catalog.
  class CartResolver
    def initialize(merchant:, lines:)
      @merchant = merchant
      @lines = Array(lines)
    end

    # [ { item:, quantity:, values:, options_total:, line_total:, notes: } ]
    def resolve
      raise PlaceService::EmptyCart, "an order needs at least one item" if @lines.empty?

      @lines.map { |line| resolve_line(line) }
    end

    def items_total(resolved = resolve)
      resolved.sum { |line| line[:line_total] }
    end

    private

    def resolve_line(line)
      item = @merchant.catalog_items.kept.find_by(id: line[:catalog_item_id])
      raise PlaceService::ItemUnavailable, "item #{line[:catalog_item_id]} is not on this menu" if item.nil?
      raise PlaceService::ItemUnavailable, "#{item.name} is sold out" unless item.is_available?

      quantity = line[:quantity].to_i
      raise PlaceService::InvalidOptions, "quantity must be at least 1" if quantity < 1

      values = resolve_option_values(item, Array(line[:option_value_ids]))
      options_total = values.sum(&:price_delta)

      {
        item: item,
        quantity: quantity,
        values: values,
        options_total: options_total,
        line_total: ((item.price + options_total) * quantity).round(2),
        notes: line[:notes]
      }
    end

    # The client enforces these rules too, but a client is a suggestion. A
    # required size missing here is an order the kitchen cannot make.
    def resolve_option_values(item, value_ids)
      values = CatalogItemOptionValue.where(id: value_ids)
                                     .where(catalog_item_option: item.options)
                                     .to_a

      unknown = value_ids.map(&:to_i) - values.map(&:id)
      raise PlaceService::InvalidOptions, "options #{unknown.join(', ')} do not belong to #{item.name}" if unknown.any?

      sold_out = values.reject(&:is_available?)
      raise PlaceService::ItemUnavailable, "#{sold_out.map(&:name).join(', ')} unavailable" if sold_out.any?

      item.options.each { |option| validate_selection(option, values) }

      values
    end

    def validate_selection(option, values)
      chosen = values.count { |value| value.catalog_item_option_id == option.id }
      minimum = option.minimum_required
      maximum = option.maximum_allowed

      raise PlaceService::InvalidOptions, "#{option.name} requires at least #{minimum}" if chosen < minimum
      raise PlaceService::InvalidOptions, "#{option.name} allows at most #{maximum}" if maximum.present? && chosen > maximum
    end
  end
end
