class CatalogCategory < ApplicationRecord
  include SoftDeletable
  belongs_to :merchant, inverse_of: :catalog_categories
  has_many :catalog_items, -> { order(:position) }, dependent: :destroy, inverse_of: :catalog_category

  validates :name, presence: true

  scope :ordered, -> { order(:position, :id) }

  # Sold-out items are INCLUDED and flagged, never filtered. A customer looking
  # for yesterday's kabab needs to see it is sold out today; removing it reads
  # as "this shop no longer sells it".
  #
  # Lives here rather than in the serializer so the preloading is one decision:
  # without it this is an N+1 per item for options and per option for values,
  # on the busiest screen in the app.
  def items_for_serialization
    catalog_items.kept.ordered.includes(:photo_attachment, options: :values)
  end

  private

  def discard_dependents!
    catalog_items.kept.update_all(deleted_at: Time.current)
  end
end
