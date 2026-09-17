module Dispatch
  # HOW FAR A COURIER MAY BE FROM A PICKUP TO BE OFFERED IT — per vehicle.
  #
  # Hamma9900's point, and it is a real one: **a motorbike should not be
  # offered a pickup a car would happily take.** The ceiling existed as one
  # global number, so the only way to be right about a bicycle was to be wrong
  # about a car.
  #
  # ── WHY THE FALLBACK GOES TO THE GLOBAL ROW AND NOT TO ZERO ────────────────
  #
  # `VehicleTypes.carries?` fails CLOSED on a vehicle it does not know, and
  # that is right there: a missing capacity entry costs one dispatch, while
  # guessing costs a courier a wasted journey and a customer their delivery.
  #
  # **This question has the opposite asymmetry and therefore the opposite
  # answer.** A radius that fails closed is not a missed dispatch, it is zero
  # dispatches for every courier on that vehicle — a silent outage that reads
  # as "dispatch is broken" rather than as a missing config row. Failing back
  # to the global ceiling costs, at worst, an offer slightly too far, which is
  # the trade `Setting::DEFINITIONS` already makes out loud: *"a courier
  # wrongly excluded is an order nobody carries, which is worse than one
  # offered slightly too far."*
  #
  # It is also nearly unreachable by design, which is the part that makes the
  # choice cheap: the per-vehicle rows are GENERATED from `VehicleTypes::ALL`,
  # so a known vehicle always has a row, and `courier_profiles.vehicle_type` is
  # `null: false, default: 0`. The fallback therefore catches a nil passed by a
  # caller that has no profile, not a courier in the database.
  module OfferRadius
    GLOBAL_KEY = "dispatch_max_offer_radius_km".freeze

    def self.key_for(vehicle_type) = "#{GLOBAL_KEY}_#{vehicle_type}"

    # The ceiling in kilometres for this vehicle. Read on every eligibility
    # check, so it follows a console edit with no deploy and no restart.
    def self.km(vehicle_type)
      key = key_for(vehicle_type)

      Setting::DEFINITIONS.key?(key) ? Setting.fetch(key) : Setting.fetch(GLOBAL_KEY)
    end
  end
end
