module Admin
  # Menu options, from the console. CLAUDE.md's data model says of these "do not
  # skip it", and until now nothing anywhere could create one.
  class CatalogItemOptionValuesController < Admin::ApplicationController
    def scoped_resource
      CatalogItemOptionValue.includes(:catalog_item_option).order(:position, :id)
    end
  end
end
