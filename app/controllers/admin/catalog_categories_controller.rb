module Admin
  # Menu management from the console. PRODUCT.md:22 puts this in phase 1 — "you
  # cannot test an order without a restaurant and a menu" — and :66 makes admin
  # the party that onboards a restaurant, which does not have the app yet.
  class CatalogCategoriesController < Admin::ApplicationController
    def scoped_resource
      CatalogCategory.includes(:merchant).order(:merchant_id, :position, :id)
    end
  end
end
