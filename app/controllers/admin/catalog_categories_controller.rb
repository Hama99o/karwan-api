module Admin
  # Menu management from the console. PRODUCT.md:22 puts this in phase 1 — "you
  # cannot test an order without a restaurant and a menu" — and :66 makes admin
  # the party that onboards a restaurant, which does not have the app yet.
  class CatalogCategoriesController < Admin::ApplicationController
    # The undo for the console's Delete, which discards (see
    # `Admin::ApplicationController#destroy`).
    def restore
      restore_resource(admin_catalog_categories_path)
    end

    def scoped_resource
      CatalogCategory.includes(:merchant).order(:merchant_id, :position, :id)
    end
  end
end
