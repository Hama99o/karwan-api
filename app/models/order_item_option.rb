# Snapshot of one chosen option value: the option's name, the value's name, and
# the price delta, all as text and numbers rather than references. A renamed
# "Large" must not silently rewrite last month's orders.
class OrderItemOption < ApplicationRecord
  include Monetary

  belongs_to :order_item, inverse_of: :selected_options

  validates :option_name, :value_name, presence: true
  validates :price_delta, numericality: true
end
