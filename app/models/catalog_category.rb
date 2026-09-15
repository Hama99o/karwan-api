class CatalogCategory < ApplicationRecord
  include SoftDeletable
  belongs_to :merchant, inverse_of: :catalog_categories
  has_many :catalog_items, -> { order(:position) }, dependent: :destroy, inverse_of: :catalog_category

  validates :name, presence: true

  scope :ordered, -> { order(:position, :id) }

  private

  def discard_dependents!
    catalog_items.kept.update_all(deleted_at: Time.current)
  end
end
