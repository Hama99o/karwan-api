class MenuCategory < ApplicationRecord
  include SoftDeletable
  belongs_to :restaurant, inverse_of: :menu_categories
  has_many :menu_items, -> { order(:position) }, dependent: :destroy, inverse_of: :menu_category

  validates :name, presence: true

  scope :ordered, -> { order(:position, :id) }

  private

  def discard_dependents!
    menu_items.kept.update_all(deleted_at: Time.current)
  end
end
