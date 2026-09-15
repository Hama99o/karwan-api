# Config as rows. Commission %, delivery fee, rider fee, cash-in-hand limit,
# default credit line, ETA average speed — all tuned weekly, none of them worth
# a deploy.
#
# `value_type` exists so no reader has to guess: a decimal read as a string is
# how "0.125" becomes zero.
class Setting < ApplicationRecord
  enum :value_type, { string: 0, integer: 1, decimal: 2, boolean: 3 }, prefix: :type

  belongs_to :updated_by, class_name: User.name, optional: true

  validates :key, presence: true, uniqueness: true
  validates :value_type, presence: true

  # Every key the app reads, with its type, default and unit. A key missing
  # from here is a typo, not a setting — `fetch` raises on it rather than
  # returning nil and letting a fee silently become zero.
  DEFINITIONS = {
    "commission_rate"        => { type: :decimal, default: "0.125", description: "Platform share of the food total (0.125 = 12.5%)" },
    # Delivery fee, distance-based. Replaces an earlier flat `delivery_fee`,
    # per Hamma9900: "we will do a simple algorithm, we will test how many
    # kilometers". Two mechanisms would mean code deciding which to trust, so
    # there is one.
    #
    # There is deliberately no `courier_fee` row: in v0 the courier keeps the
    # whole delivery fee. `orders.courier_fee` is still its own column, so the
    # platform can later take a cut of delivery without a migration — but a cut
    # now would pay couriers less than the customer already believes, and
    # courier supply is the scarce side.
    "delivery_base_fee"      => { type: :decimal, default: "50.0", currency: "AFN", description: "Charged on every delivery before distance" },
    "delivery_fee_per_km"    => { type: :decimal, default: "20.0", currency: "AFN", description: "Added per straight-line kilometre" },
    "delivery_minimum_fee"   => { type: :decimal, default: "80.0", currency: "AFN", description: "Floor, so a very short delivery is still worth taking" },
    "cash_in_hand_limit"     => { type: :decimal, default: "3000.0", currency: "AFN", description: "Above this a rider must settle before taking more work" },
    "default_credit_line"    => { type: :decimal, default: "500.0", currency: "AFN", description: "How far a new rider's wallet may go below zero" },
    "eta_average_speed_kmh"  => { type: :decimal, default: "18.0", description: "Straight-line distance / this = ETA. Calibrate from real deliveries." },
    "dispatch_offer_ttl_sec" => { type: :integer, default: "60", description: "How long a rider has to answer an offer before it moves on" },
    "dispatch_max_offers"    => { type: :integer, default: "5", description: "Riders tried before the order is surfaced to admin" },
    # OTP SEND limits. These are a BILL, not only a security control: SMS is one
    # of exactly two recurring costs in v0, and an unthrottled request endpoint
    # is someone else spending the owner's money. They are settings rather than
    # constants so a number can be tightened during an attack without a deploy.
    #
    # Two limits, because they stop different things. The burst limit stops
    # somebody hammering one number — harassment, and a fast bill. The daily
    # limit caps what a single number can ever cost us, however patient the
    # caller is.
    "otp_max_sends_per_window" => { type: :integer, default: "3", description: "OTP messages allowed to one number within the burst window" },
    "otp_send_window_minutes"  => { type: :integer, default: "15", description: "Length of the OTP burst window, in minutes" },
    "otp_max_sends_per_day"    => { type: :integer, default: "10", description: "Hard daily cap on OTP messages to one number" },

    # Routing. The OSRM ADDRESS is deliberately NOT here — it comes from
    # OSRM_BASE_URL in the environment, because a Setting row feeding an
    # outbound HTTP host is an SSRF surface (brakeman flagged exactly that) and
    # because a service address is infrastructure rather than a number the
    # owner tunes. What stays here is policy: the on/off switch, the timeouts
    # and the snap threshold.
    # ~500x the measured p95 of 3.9 ms, and still not a hang. A quote sits on
    # the path an order takes.
    "routing_open_timeout_seconds" => { type: :integer, default: "1", description: "Connect timeout for a routing call" },
    "routing_read_timeout_seconds" => { type: :integer, default: "2", description: "Read timeout for a routing call, after which we fall back to a straight line" },
    # DEFAULTS TO straight_line. Switching to `osrm` raises fares ~29% and is
    # Hamma9900's decision; a setting means he says yes once with no deploy.
    "routing_distance_source" => { type: :string, default: "straight_line", description: "Where a fare's distance comes from: straight_line or osrm" },
    # Above this the pin is not on the road network — Kabul is full of walled
    # compounds. Recorded, not corrected: the landmark note and the phone
    # number do the real work.
    "routing_snap_warning_metres" => { type: :decimal, default: "150.0", description: "Snap distance above which a pin is flagged as off the road network" },

    "support_phone"          => { type: :string,  default: "", description: "Shown in all three apps. Delivery is an ops business with an app attached." },

    # Ride fares. Present so the numbers are tunable from day one, exactly like
    # the delivery fee — NOT because the ride product is built. Distance comes
    # from the straight line and eta_average_speed_kmh, not from a router.
    "trip_base_fare"         => { type: :decimal, default: "50.0", currency: "AFN", description: "Charged on every trip before distance" },
    "trip_fare_per_km"       => { type: :decimal, default: "25.0", currency: "AFN", description: "Added per straight-line kilometre" },
    "trip_fare_per_minute"   => { type: :decimal, default: "2.0", currency: "AFN", description: "Added per estimated minute" },
    "trip_minimum_fare"      => { type: :decimal, default: "80.0", currency: "AFN", description: "Floor, so a very short trip is still worth taking" },
    "trip_commission_rate"   => { type: :decimal, default: "0.125", description: "Platform share of a trip fare (0.125 = 12.5%)" }
  }.freeze

  # Raises on an unknown key. A silent nil here becomes a zero fee in
  # production, which is worse than a 500 in development.
  def self.fetch(key)
    definition = DEFINITIONS.fetch(key.to_s) do
      raise KeyError, "unknown setting #{key.inspect} — add it to Setting::DEFINITIONS"
    end

    record = find_by(key: key.to_s)
    cast(record&.value || definition[:default], definition[:type])
  end

  def self.cast(raw, type)
    case type.to_sym
    when :integer then raw.to_i
    when :decimal then BigDecimal(raw.to_s.presence || "0")
    when :boolean then ActiveModel::Type::Boolean.new.cast(raw) || false
    else raw.to_s
    end
  end

  def self.seed_defaults!
    DEFINITIONS.each do |key, definition|
      record = find_or_initialize_by(key: key)
      record.value_type = definition[:type]
      record.currency = definition[:currency]
      record.description = definition[:description]
      record.value = definition[:default] if record.value.nil?
      record.save!
    end
  end

  def typed_value
    self.class.cast(value, value_type)
  end
end
