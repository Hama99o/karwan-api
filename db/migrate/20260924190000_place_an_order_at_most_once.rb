# A retry of "place order" whose first answer was lost must not place a second
# order. The app sends a key it made when checkout opened; the order keeps it,
# and the index is what makes two simultaneous attempts one order.
# `request_fingerprint` is what the key is compared against: the same key with
# a different basket is a different request, not a repeat.
#
# Nullable, so an app build that sends no key keeps working exactly as before.
class PlaceAnOrderAtMostOnce < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :idempotency_key, :string
    add_column :orders, :request_fingerprint, :string
    add_index :orders, %i[customer_id idempotency_key], unique: true,
                                                          where: "idempotency_key IS NOT NULL",
                                                          name: "index_orders_on_customer_and_idempotency_key"
  end
end
