# A snapshot of what was ordered, at the price it was ordered at. Never join
# live to catalog_items to render a historical order — menus change daily.
class OrderItem < ApplicationRecord
  include Monetary

  belongs_to :order
  # Provenance only, and nullable: the menu item may be renamed or deleted.
  belongs_to :catalog_item, optional: true

  has_many :selected_options, class_name: OrderItemOption.name, dependent: :destroy,
           inverse_of: :order_item

  validates :name, presence: true
  validates :quantity, numericality: { greater_than: 0 }
  validates :unit_price, :line_total, numericality: { greater_than_or_equal_to: 0 }
  validate  :line_total_matches_parts

  # (unit_price + options_total) * quantity. Computed here so the client never
  # has to, and never gets to disagree.
  def expected_line_total
    ((unit_price || 0) + (options_total || 0)) * (quantity || 0)
  end

  private

  def line_total_matches_parts
    return if [ unit_price, options_total, quantity, line_total ].any?(&:blank?)
    return if (line_total - expected_line_total).abs <= Monetary::ROUNDING_TOLERANCE

    errors.add(:line_total, "must equal (unit_price + options_total) * quantity (#{expected_line_total})")
  end
end
