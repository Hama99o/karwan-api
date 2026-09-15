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
    "delivery_fee"           => { type: :decimal, default: "100.0", currency: "AFN", description: "Charged to the customer per order" },
    "courier_fee"            => { type: :decimal, default: "100.0", currency: "AFN", description: "Paid to the courier per food delivery" },
    "cash_in_hand_limit"     => { type: :decimal, default: "3000.0", currency: "AFN", description: "Above this a rider must settle before taking more work" },
    "default_credit_line"    => { type: :decimal, default: "500.0", currency: "AFN", description: "How far a new rider's wallet may go below zero" },
    "eta_average_speed_kmh"  => { type: :decimal, default: "18.0", description: "Straight-line distance / this = ETA. Calibrate from real deliveries." },
    "dispatch_offer_ttl_sec" => { type: :integer, default: "60", description: "How long a rider has to answer an offer before it moves on" },
    "dispatch_max_offers"    => { type: :integer, default: "5", description: "Riders tried before the order is surfaced to admin" },
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
