module Admin
  # Menu options, from the console. CLAUDE.md's data model says of these "do not
  # skip it", and until now nothing anywhere could create one.
  class CatalogItemOptionsController < Admin::ApplicationController
    def scoped_resource
      CatalogItemOption.includes(:catalog_item).order(:position, :id)
    end
  end
end
