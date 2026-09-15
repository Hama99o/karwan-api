class MerchantCategoryAssignment < ApplicationRecord
  belongs_to :merchant
  belongs_to :merchant_category

  validates :merchant_category_id, uniqueness: { scope: :merchant_id }
end
