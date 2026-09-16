# WHAT A COURIER RIDES, and what it can carry — defined once, in a plain
# module that depends on nothing.
#
# ── WHY THIS IS NOT ON `CourierProfile` ─────────────────────────────────────
#
# It was, and that was a latent boot failure. `Trip`, `Order` and
# `PricingRate` all need the same vehicle mapping, so their class bodies
# called `CourierProfile.vehicle_types` and read `CourierProfile::SEATS` — and
# a class body that reaches into another model makes the two LOAD-ORDER
# DEPENDENT. Under eager loading, `Trip` could be reached while
# `CourierProfile` was still part-way through its own body, and
# `CourierProfile::SEATS` did not exist yet:
#
#   app/models/trip.rb:79: uninitialized constant CourierProfile::SEATS
#
# It reproduced in `RAILS_ENV=test bin/rails runner`, passed `zeitwerk:check`,
# and passed the whole suite — and **production eager-loads**, so it was a
# boot failure waiting for a load order nobody had hit yet. The same shape as
# `Roles` and `SizeClasses`: a shared vocabulary belongs in a module every
# model can read without loading another model.
#
# ── The integers are a contract ─────────────────────────────────────────────
# They are stored on `courier_profiles`, `trips`, `orders` and `pricing_rates`.
# Append, never renumber — renumbering would turn every car in the database
# into a rishka.
module VehicleTypes
  ALL = {
    motorbike: 0,
    bicycle: 1,
    car: 2,
    on_foot: 3,
    # Hamma9900's own words, and two different vehicles: a `rishka` is the
    # common Kabul three-wheeler; a `zarang` is one built for heavy goods, and
    # his example is a bed.
    rishka: 4,
    zarang: 5
  }.freeze

  # ── WHAT EACH ONE CARRIES ───────────────────────────────────────────────────
  #
  # PROVISIONAL. This is a guess, not a researched fact, and Hamma9900 has not
  # confirmed the ordering. **The least certain pair is car versus rishka** —
  # both are `large` here, and a rishka may well take bulkier goods than a car
  # even though a car takes more people. Correcting it is ONE LINE, which is
  # the whole argument for a constant rather than a column: a column would be
  # this same value copied onto every courier's row plus a migration to change
  # it.
  #
  # The ordering is NOT a ladder from bicycle to car: a zarang beats a car for
  # furniture, which is why capacity is looked up per vehicle rather than
  # derived from the integers above.
  CARRIES = {
    on_foot: :small,
    bicycle: :small,
    motorbike: :medium,
    car: :large,
    rishka: :large,
    zarang: :bulky
  }.freeze

  # ── HOW MANY PASSENGERS ─────────────────────────────────────────────────────
  #
  # Also provisional. The least certain figure is `rishka`, which is 3 here — a
  # Kabul rishka commonly takes three across the back, but it depends on the
  # body. `zarang` is 2 because it is built for goods rather than people, and a
  # bicycle and a pedestrian seat nobody: a passenger on a bicycle is not a
  # service we offer.
  SEATS = {
    on_foot: 0,
    bicycle: 0,
    motorbike: 1,
    rishka: 3,
    car: 4,
    zarang: 2
  }.freeze

  # The most anybody can ask for. A plain constant rather than a call into a
  # model, so a validation can use it in a class body safely.
  MAX_SEATS = SEATS.values.max

  # Fails CLOSED on an unknown vehicle: one added to the enum without a
  # capacity is one nobody should be offered a bulky job or a passenger on. A
  # missing entry costs a dispatch; failing open would cost a courier a wasted
  # journey and a customer their delivery.
  def self.carries?(vehicle_type, size_class)
    capacity = CARRIES[vehicle_type&.to_sym]
    return false if capacity.nil?

    SizeClasses.covers?(capacity, size_class)
  end

  def self.seats?(vehicle_type, passenger_count)
    SEATS.fetch(vehicle_type&.to_sym, 0) >= passenger_count.to_i
  end

  # The types that could take a job of this size, for asking a whole fleet in
  # one query instead of per courier.
  def self.carrying(size_class)
    CARRIES.select { |_type, capacity| SizeClasses.covers?(capacity, size_class) }
           .keys.map(&:to_s)
  end

  # The types that seat this many people — used to filter the classes a
  # passenger is OFFERED, so a family of four never sees a motorbike fare they
  # cannot use.
  def self.seating(passenger_count)
    SEATS.select { |_type, seats| seats >= passenger_count.to_i }.keys.map(&:to_s)
  end
end
