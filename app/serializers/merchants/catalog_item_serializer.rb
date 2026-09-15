module Merchants
  class CatalogItemSerializer < ApplicationSerializer
    identifier :id

    fields :name, :description, :price, :currency, :is_available, :position

    field :prep_time_minutes do |item|
      item.prep_time_minutes
    end

    field :catalog_category_id do |item|
      item.catalog_category_id
    end
  end
end
