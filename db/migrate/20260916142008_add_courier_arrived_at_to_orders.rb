# "YOUR COURIER IS AT THE GATE."
#
# Hamma9900 asked for customer and courier to be able to reach each other
# **especially at the arrival moment** — and the thing that actually solves
# that is not a chat screen, it is a NOTIFICATION: a message inside the app
# reaches somebody who has the app open, and the person waiting for a delivery
# does not. A push reaches them in the kitchen.
#
# A RIDE ALREADY HAD THIS: `trips.arrived_at`, with `arrived` as a real state,
# because a passenger who is not at the kerb is the whole problem of a taxi.
# An ORDER had nothing — the step list has `go_to_customer` with no
# `status_after`, so the courier could be standing at the gate and the system
# did not know.
#
# ── WHY A TIMESTAMP AND NOT A STATUS ──────────────────────────────────────
#
# `Order`'s state machine is placed → accepted → preparing → ready →
# picked_up → delivered, and every state carries a timeout, an actor and a set
# of permitted transitions. Arrival is not a state in that sense: nothing
# expires because of it, nobody else acts on it, and the order is still
# `picked_up` either way. Adding a state would mean a new timeout, new
# transition rules and a migration for every existing row — to record a fact
# that is only ever read as "has he arrived yet".
#
# So: a timestamp, set once, which is also what makes the notification
# idempotent. A courier tapping twice must not ring a customer twice.
class AddCourierArrivedAtToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :courier_arrived_at, :datetime
  end
end
