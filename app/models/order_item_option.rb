# Snapshot of one chosen option value: the option's name, the value's name, and
# the price delta, all as text and numbers rather than references. A renamed
# "Large" must not silently rewrite last month's orders.
class OrderItemOption < ApplicationRecord
  include Monetary

  belongs_to :order_item, inverse_of: :selected_options

  # WHICH value this was, for ONE purpose: re-ordering. Never for display and
  # never for arithmetic — `value_name` and `price_delta` above are the record
  # of what was bought and for how much, and they stay authoritative however
  # the live catalog changes.
  #
  # Nullable and `on_delete: :nullify`: a merchant deleting an option value
  # must neither be blocked by a historical order nor cascade into one. The
  # receipt survives; only the re-order shortcut is lost.
  belongs_to :catalog_item_option_value, optional: true

  validates :option_name, :value_name, presence: true
  validates :price_delta, numericality: true
end
