module Admin
  # The browse taxonomy. Routed because customers already filter by it and
  # nothing could assign a merchant to one.
  class MerchantCategoriesController < Admin::ApplicationController
    def scoped_resource
      MerchantCategory.order(:position, :slug)
    end
  end
end
