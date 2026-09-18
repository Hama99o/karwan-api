module Admin
  # Opening hours, set by an operator because PRODUCT.md says admin onboards
  # restaurants and the shop does not edit its own identity in v0.
  class MerchantOpeningHoursController < Admin::ApplicationController
    def scoped_resource
      MerchantOpeningHour.includes(:merchant).order(:merchant_id, :day_of_week, :opens_at)
    end
  end
end
