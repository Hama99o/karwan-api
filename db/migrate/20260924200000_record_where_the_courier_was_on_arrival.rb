# "I am at the gate" on a DELIVERY recorded when, and not where. A ride's
# arrival goes through the state machine, whose transition row already carries
# the courier's position; a delivery has no arrival state, so its moment was a
# bare timestamp — and "he said he was at my gate and he wasn't" was answerable
# on a ride and unanswerable on a delivery.
#
# The same trio as `status_transitions`: the position, and the time of the FIX,
# so the evidence carries its own age. Nullable: a courier with no fix yet still
# arrives.
class RecordWhereTheCourierWasOnArrival < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :courier_arrived_latitude, :decimal, precision: 10, scale: 6
    add_column :orders, :courier_arrived_longitude, :decimal, precision: 10, scale: 6
    add_column :orders, :courier_arrived_located_at, :datetime
  end
end
