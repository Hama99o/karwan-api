class MenuCategory < ApplicationRecord
  belongs_to :restaurant, inverse_of: :menu_categories
  has_many :menu_items, -> { order(:position) }, dependent: :destroy, inverse_of: :menu_category

  validates :name, presence: true

  scope :ordered, -> { order(:position, :id) }
end
