class CatalogItemOptionValue < ApplicationRecord
  include Monetary

  belongs_to :catalog_item_option, inverse_of: :values

  validates :name, presence: true
  # Negative deltas are legal — "no rice, -20" is a real menu line.
  validates :price_delta, numericality: true

  scope :available, -> { where(is_available: true) }
  scope :ordered,   -> { order(:position, :id) }
end
