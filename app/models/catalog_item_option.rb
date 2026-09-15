# One level deep, deliberately: values have no children. This is a menu, not a
# configurator.
class CatalogItemOption < ApplicationRecord
  enum :selection_type, { single: 0, multiple: 1 }, prefix: :select

  belongs_to :catalog_item, inverse_of: :options
  has_many :values, -> { order(:position) }, class_name: CatalogItemOptionValue.name,
           dependent: :destroy, inverse_of: :catalog_item_option

  validates :name, presence: true
  validates :min_selections, numericality: { greater_than_or_equal_to: 0 }
  validates :max_selections, numericality: { greater_than: 0 }, allow_nil: true
  validate  :max_not_below_min
  validate  :single_select_picks_one

  scope :ordered, -> { order(:position, :id) }

  # How many values a customer must pick. `required` and min_selections can
  # disagree; this is the single answer both the API and the app use, so a
  # required option with min 0 still demands a choice.
  def minimum_required
    required? ? [ min_selections, 1 ].max : min_selections
  end

  def maximum_allowed
    return 1 if select_single?

    max_selections
  end

  private

  def max_not_below_min
    return if max_selections.blank? || min_selections.blank?
    return if max_selections >= min_selections

    errors.add(:max_selections, "cannot be below min_selections")
  end

  def single_select_picks_one
    return unless select_single?
    return if max_selections.blank? || max_selections == 1

    errors.add(:max_selections, "must be 1 for a single-select option")
  end
end
