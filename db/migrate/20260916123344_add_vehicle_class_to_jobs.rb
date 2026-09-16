# WHICH VEHICLE, FROZEN ON THE JOB — and for a ride, how many people.
#
# ── trips.vehicle_type: chosen by the PASSENGER, before the quote ──────────
# This is what resolves the conflict between "the fare depends on the vehicle"
# and "the fare is quoted upfront and never metered" (correction 13): the class
# is chosen BEFORE the price is calculated, so the price can depend on it and
# still be honest. Dispatch then offers the trip only to couriers of that
# class — a passenger who paid for a car must not be collected on a motorbike.
#
# Nullable, because trips placed before this column exists chose nothing, and a
# nil class means "any vehicle" to dispatch rather than "no vehicle".
#
# ── trips.passenger_count: an input to the quote, so it is in the snapshot ──
# It does two things, both of which reuse machinery that already exists: it is
# a capacity check (the same shape as cargo size, on a people axis), and it
# FILTERS THE CLASSES A PASSENGER MAY CHOOSE. That closes a trap in the picker:
# without it a family of four could select the cheapest class and be
# undispatchable, having already agreed a fare.
#
# ── orders.courier_vehicle_type: known only at ASSIGNMENT ─────────────────
# The delivery courier fee varies by vehicle, and we do not know who will
# accept until they do — so unlike every other amount on an order, the courier
# fee cannot be frozen at quote time. It freezes at assignment, and this column
# is what makes the payout explainable afterwards: "why was this 140?" is
# answered by the vehicle that earned it.
#
# The customer-facing total is untouched and still freezes at the quote, so
# correction 13's purpose holds exactly: the customer is never surprised by a
# number. Only its wording needed amending, which Hamma9901 has done.
class AddVehicleClassToJobs < ActiveRecord::Migration[8.1]
  def change
    add_column :trips, :vehicle_type, :integer
    add_column :trips, :passenger_count, :integer, null: false, default: 1
    add_column :orders, :courier_vehicle_type, :integer

    # Dispatch asks "which live trips want a car?" on every offer sweep.
    add_index :trips, %i[vehicle_type status]
  end
end
