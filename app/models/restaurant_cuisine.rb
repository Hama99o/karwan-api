class RestaurantCuisine < ApplicationRecord
  belongs_to :restaurant
  belongs_to :cuisine

  validates :cuisine_id, uniqueness: { scope: :restaurant_id }
end
