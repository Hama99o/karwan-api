# One two-part tariff, for one audience, on one vehicle class.
#
# `Setting` holds scalars; this holds anything that varies by vehicle. See the
# migration for why the two demand types are deliberately asymmetric — the
# passenger picks a ride class and sees its price, while a delivery has one
# customer fee and the vehicle affects only what the courier earns.
class PricingRate < ApplicationRecord
  include Monetary

  # `customer` rows are what somebody is charged. `courier` rows are what
  # somebody is paid. Naming the audience on the row is what lets one table
  # hold both without a column meaning two different things.
  enum :audience, { customer: 0, courier: 1 }, prefix: :for

  JOB_KINDS = [ Order::JOB_KIND, Trip::JOB_KIND ].freeze

  validates :job_kind, presence: true, inclusion: { in: JOB_KINDS }
  validates :base, :per_km, :per_minute, :minimum,
            numericality: { greater_than_or_equal_to: 0 }
  validates :vehicle_type, uniqueness: { scope: %i[job_kind audience] }

  # THE SAME INTEGERS AS `courier_profiles.vehicle_type`, taken from that enum
  # rather than rebuilt here — so a rate and a courier can never disagree about
  # what a vehicle is.
  #
  # I wrote this as `CARRIES.keys.each_with_index` first, which looks
  # equivalent and is not: `CARRIES` is ordered by capacity (on_foot first) and
  # the enum is ordered by when each vehicle was added (motorbike first), so
  # every rate would have been stored against the wrong vehicle — a car's fare
  # charged for a rishka, silently. Derive the mapping, never restate it.
  #
  # Nil means "any vehicle", which is what a rate with no class dimension is.
  enum :vehicle_type, CourierProfile.vehicle_types, prefix: :by

  # ── THE DEFAULTS, AND WHERE THE NUMBERS COME FROM ──────────────────────────
  #
  # Seeded by `db/seeds/reference.rb`, editable in the console with no deploy —
  # correction 13 is that pricing stays stupid and admin-tunable, and
  # Hamma9900 will calibrate against the market. He said 80% accuracy is
  # enough.
  #
  # RIDES hit the two figures he gave: **a rider ≈ 150 AFN for 10 km, a driver
  # ≈ 200**. The arithmetic is shown so he can see how each one is composed and
  # move one part without guessing:
  #
  #   10 km at `eta_average_speed_kmh` (18) is ~33 minutes, so
  #     motorbike  30 + (8 × 10) + (1.2 × 33) ≈ 150   ← his "rider"
  #     rishka     35 + (9 × 10) + (1.5 × 33) ≈ 175
  #     car        40 + (10 × 10) + (1.8 × 33) ≈ 200  ← his "driver"
  #
  # DELIVERY COURIER PAY reproduces today's fee EXACTLY for every vehicle
  # (50 + 20/km, floor 80 — the same `delivery_*` settings), so introducing
  # this table changes no money at all. v0 has the courier keeping the whole
  # delivery fee; the per-vehicle dimension now EXISTS and is a number he types
  # when he wants it, rather than a migration. A structural change that quietly
  # repriced every delivery would be a bad way to find out this table works.
  #
  # `on_foot` gets no ride row: nobody hails a pedestrian. `bicycle` gets none
  # either — a passenger on a bicycle is not a service we offer.
  DEFAULTS = [
    { job_kind: "ride", audience: :customer, vehicle_type: :motorbike,
      base: 30, per_km: 8, per_minute: 1.2, minimum: 60, is_selectable: true, position: 1 },
    { job_kind: "ride", audience: :customer, vehicle_type: :rishka,
      base: 35, per_km: 9, per_minute: 1.5, minimum: 70, is_selectable: true, position: 2 },
    { job_kind: "ride", audience: :customer, vehicle_type: :car,
      base: 40, per_km: 10, per_minute: 1.8, minimum: 80, is_selectable: true, position: 3 },
    { job_kind: "ride", audience: :customer, vehicle_type: :zarang,
      base: 35, per_km: 9, per_minute: 1.5, minimum: 70, is_selectable: true, position: 4 },

    # THE ANY-VEHICLE RIDE ROW, reproducing today's `trip_*` settings exactly
    # (50 + 25/km + 2/min, floor 80). It is what a caller that has not asked the
    # class gets — so introducing this table repriced nothing, and the per-class
    # rows above are what the passenger actually sees once the picker exists.
    { job_kind: "ride", audience: :customer, vehicle_type: nil,
      base: 50, per_km: 25, per_minute: 2, minimum: 80 },

    { job_kind: "delivery", audience: :courier, vehicle_type: :bicycle,
      base: 50, per_km: 20, per_minute: 0, minimum: 80 },
    { job_kind: "delivery", audience: :courier, vehicle_type: :motorbike,
      base: 50, per_km: 20, per_minute: 0, minimum: 80 },
    { job_kind: "delivery", audience: :courier, vehicle_type: :rishka,
      base: 50, per_km: 20, per_minute: 0, minimum: 80 },
    { job_kind: "delivery", audience: :courier, vehicle_type: :car,
      base: 50, per_km: 20, per_minute: 0, minimum: 80 },
    { job_kind: "delivery", audience: :courier, vehicle_type: :zarang,
      base: 50, per_km: 20, per_minute: 0, minimum: 80 },
    { job_kind: "delivery", audience: :courier, vehicle_type: :on_foot,
      base: 50, per_km: 20, per_minute: 0, minimum: 80 },
    # The any-vehicle fallback, so a vehicle added to the enum without a rate
    # earns today's fee rather than raising on a live dispatch.
    { job_kind: "delivery", audience: :courier, vehicle_type: nil,
      base: 50, per_km: 20, per_minute: 0, minimum: 80 }
  ].freeze

  def self.seed_defaults!
    DEFAULTS.each do |attrs|
      row = find_or_initialize_by(attrs.slice(:job_kind, :audience, :vehicle_type))
      # `find_or_initialize` then assign only on CREATE: re-seeding must never
      # overwrite a number Hamma9900 typed in the console.
      next if row.persisted?

      row.update!(attrs)
    end
  end

  scope :selectable, -> { where(is_selectable: true).order(:position) }
  scope :for_job, ->(job_kind) { where(job_kind: job_kind) }

  # WHAT THIS JOB COSTS on this tariff. Rounded to the minor unit here, once,
  # rather than at every call site — `Monetary` exists because edu-safi shipped
  # a total that added afghanis to dollars.
  #
  # `duration_minutes` is optional because a delivery prices on distance alone;
  # a nil duration contributes nothing rather than raising, so one formula
  # serves both demand types.
  def amount_for(distance_km:, duration_minutes: nil)
    computed = base +
               (per_km * BigDecimal(distance_km.to_s)) +
               (per_minute * BigDecimal((duration_minutes || 0).to_s))

    [ computed, minimum ].max.round(2)
  end

  # The one rate that applies: the class's own row, else the any-vehicle row,
  # else the DECLARED DEFAULT for that combination.
  #
  # The last fallback mirrors `Setting.fetch` deliberately — a rate that has not
  # been seeded yet must not become a zero fare, and a test must not have to
  # seed a table to price a ride. If the combination is not declared at all,
  # that is a typo rather than a rate, so it raises with the same reasoning
  # `Setting.fetch` raises on an unknown key.
  def self.fetch(job_kind:, audience:, vehicle_type: nil)
    scope = where(job_kind: job_kind, audience: audiences.fetch(audience.to_s))
    rate = scope.find_by(vehicle_type: vehicle_types[vehicle_type.to_s]) if vehicle_type.present?
    rate ||= scope.find_by(vehicle_type: nil)

    rate || declared_default(job_kind, audience, vehicle_type)
  end

  # An unsaved row built from `DEFAULTS`, which behaves exactly like a saved one
  # for pricing. Not persisted here: a read must not write, or a quote on a
  # replica would fail and a seed would stop being the one place rows are made.
  def self.declared_default(job_kind, audience, vehicle_type)
    attrs = DEFAULTS.find do |row|
      row[:job_kind] == job_kind.to_s && row[:audience].to_s == audience.to_s &&
        row[:vehicle_type].to_s == vehicle_type.to_s
    end
    attrs ||= DEFAULTS.find do |row|
      row[:job_kind] == job_kind.to_s && row[:audience].to_s == audience.to_s &&
        row[:vehicle_type].nil?
    end

    if attrs.nil?
      raise KeyError,
            "no #{audience} rate declared for a #{job_kind} on #{vehicle_type || 'any vehicle'} " \
            "— add it to PricingRate::DEFAULTS"
    end

    new(attrs)
  end
end
