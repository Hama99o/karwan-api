# WAS THE ALERT HEARD, not merely delivered.
#
# PRODUCT.md: the incoming order is "loud and repeating **until acknowledged**",
# on "a cheap tablet propped on a counter in a noisy kitchen", and a merchant
# who never hears it is the most damaging state in the system.
#
# The console already counts pushes that reached NO DEVICE
# (`needs_human_contact` on the `merchant.alerted` audit row). This records the
# other half, which is worse because it looks fine: a push that WAS delivered,
# to a tablet nobody looked at. Until now the two were indistinguishable from
# the server, and only one of them was visible.
#
# Nullable on purpose — the absence IS the state ops needs to see, and a
# default would erase the distinction between "not yet" and "never".
class AddMerchantAcknowledgementToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :merchant_acknowledged_at, :datetime
    add_reference :orders, :merchant_acknowledged_by, foreign_key: { to_table: :users }, null: true

    # The ops query is "live orders, alerted, not acknowledged" — a partial
    # index so it stays cheap as the table grows, and it indexes the NULLs
    # because the nulls are what is being looked for.
    add_index :orders, :created_at, where: "merchant_acknowledged_at IS NULL",
                                    name: "index_orders_unacknowledged"
  end
end
