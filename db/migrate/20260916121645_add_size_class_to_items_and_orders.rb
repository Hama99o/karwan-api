# HOW BIG IS THIS DELIVERY?
#
# Nothing anywhere expressed it, so **a bed and a book were indistinguishable
# to dispatch** — and a bed-sized delivery could be offered to a courier on a
# bicycle, who would accept it in good faith, ride there, and discover he
# cannot carry it. That failure costs the customer, the merchant and the
# courier at once, and the system had no way to have known.
#
# It matters because of correction 7's wider point: this platform carries goods
# from any kind of store, and Hamma9900's own examples have been books and now
# a bed. Those are not the same delivery. He added `zarang` — a rishka built
# for heavy goods — for exactly this.
#
# TWO COLUMNS, and the second is the one that matters in a year:
#
#   catalog_items.size_class     — the merchant knows their own goods. A
#                                  restaurant never touches this; a furniture
#                                  shop sets "bulky" on beds once. The cheapest
#                                  accurate source of truth there is.
#   orders.required_size_class   — THE SNAPSHOT, resolved at placement as the
#                                  maximum over the order's items. Exactly like
#                                  the prices (one-way door #1): if the merchant
#                                  re-classifies an item next month, last
#                                  month's order must not change what it needed.
#
# Both default to the smallest and are NOT NULL, so every existing row means
# "small" — which is true: everything ordered so far has been food.
class AddSizeClassToItemsAndOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :catalog_items, :size_class, :integer, null: false, default: 0
    add_column :orders, :required_size_class, :integer, null: false, default: 0

    # Dispatch asks "which live orders need more than a motorbike?" — rare
    # enough to be worth an index only alongside the status it is asked with.
    add_index :orders, %i[required_size_class status]
  end
end
