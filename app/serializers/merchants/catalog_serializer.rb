module Merchants
  # The merchant's own catalog, as they manage it.
  #
  # Different from the customer's view of the same rows: this one carries the
  # discarded flag and the position, because the merchant is editing structure,
  # not choosing dinner. Same records, two shapes.
  class CatalogSerializer < ApplicationSerializer
    identifier :id

    fields :name, :position

    field :item_count do |category|
      category.catalog_items.kept.size
    end

    field :items do |category|
      category.catalog_items.kept.ordered.map do |item|
        {
          id: item.id,
          name: item.name,
          description: item.description,
          price: item.price,
          currency: item.currency,
          is_available: item.is_available?,
          prep_time_minutes: item.prep_time_minutes,
          position: item.position,
          options: item.options.ordered.map do |option|
            {
              id: option.id, name: option.name, selection_type: option.selection_type,
              required: option.required, minimum_required: option.minimum_required,
              maximum_allowed: option.maximum_allowed,
              values: option.values.ordered.map do |value|
                { id: value.id, name: value.name, price_delta: value.price_delta,
                  is_available: value.is_available? }
              end
            }
          end
        }
      end
    end
  end
end
