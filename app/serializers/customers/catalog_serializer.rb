module Customers
  # A merchant's catalog, grouped the way the merchant groups it.
  #
  # Sold-out items are INCLUDED and flagged, not filtered out. A customer
  # looking for the kabab that was there yesterday needs to see that it is sold
  # out today; silently removing it reads as "this shop no longer sells it".
  class CatalogSerializer < ApplicationSerializer
    identifier :id

    fields :name, :position

    field :items do |category, options|
      category.items_for_serialization.map do |item|
        {
          id: item.id,
          name: item.name,
          description: item.description,
          price: item.price,
          currency: item.currency,
          is_available: item.is_available?,
          prep_time_minutes: item.effective_prep_time_minutes,
          photo_url: (Rails.application.routes.url_helpers.rails_blob_path(item.photo, only_path: true) if item.photo.attached?),
          options: item.options.map do |option|
            {
              id: option.id,
              name: option.name,
              selection_type: option.selection_type,
              # `minimum_required` rather than the raw `required` flag: the two
              # can disagree, and this is the single answer the client and the
              # server both use.
              minimum_required: option.minimum_required,
              maximum_allowed: option.maximum_allowed,
              values: option.values.select(&:is_available?).map do |value|
                { id: value.id, name: value.name, price_delta: value.price_delta,
                  currency: value.currency }
              end
            }
          end
        }
      end
    end
  end
end
