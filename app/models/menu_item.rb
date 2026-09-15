class MenuItem < ApplicationRecord
  include Monetary

  belongs_to :restaurant
  belongs_to :menu_category, inverse_of: :menu_items

  has_many :options, -> { order(:position) }, class_name: MenuItemOption.name,
           dependent: :destroy, inverse_of: :menu_item
  # Nullified, not destroyed: order_items reference this for provenance only and
  # carry their own name/price snapshot, so deleting a menu item must not delete
  # order history.
  has_many :order_items, dependent: :nullify

  has_one_attached :photo

  validates :name, presence: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }
  validates :prep_time_minutes, numericality: { greater_than: 0 }, allow_nil: true

  scope :available, -> { where(is_available: true) }
  scope :ordered,   -> { order(:position, :id) }

  # The item's own prep time if set, else the restaurant's.
  def effective_prep_time_minutes
    prep_time_minutes || restaurant.prep_time_minutes
  end

  # Keep the denormalised restaurant_id honest — it is what every scope filters
  # on, so a row where it disagrees with the category is invisible to the menu
  # it belongs to.
  before_validation :inherit_restaurant_from_category

  private

  def inherit_restaurant_from_category
    self.restaurant_id ||= menu_category&.restaurant_id
  end
end
