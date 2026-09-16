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
    # ── THE TIERS ─────────────────────────────────────────────────────────────
    #
    # A SCALAR, so it is a `Setting` and not a `pricing_rates` dimension: the
    # premium uplift is the same proportion whatever the vehicle, and adding a
    # tier axis to the rate table would double every row to express one number.
    #
    # It multiplies the customer-facing amount only — the delivery fee, or the
    # ride fare. What the courier earns is unchanged by it: he is paid for the
    # run he did, and a premium run is the same run with nothing else on it.
    # The uplift is the platform's, because what premium buys is the CAPACITY
    # we hold empty for it.
    "premium_price_multiplier" => { type: :decimal, default: "1.3", description: "Premium costs this much more than normal (1.3 = +30%). Applies to the customer's fee or fare, never to the courier's pay." },
    # How many jobs a courier may carry at once, counting the one he has. 1
    # means no batching at all, which is v0: the tier is RECORDED now because
    # consent cannot be retrofitted, and honoured by never batching until this
    # is raised.
    "batch_max_jobs"         => { type: :integer, default: "1", description: "Jobs a courier may hold at once, including the current one. 1 = no batching. Raise to 3 when there is enough demand to combine runs." },
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
    # DEFAULTS TO `osrm`, because Hamma9900 has decided: *"distances are not
    # measured by roads"* and straight-line is unfair. Measured on four Kabul
    # pairs, road distance is 1.24–1.47× the straight line, which moves the
    # delivery fee +15% to +20% on ordinary runs and by nothing on a short hop
    # where the minimum fee absorbs it.
    #
    # THE DEFAULT MATTERS AS MUCH AS THE ROW. It was `straight_line`, and the
    # row was never flipped — so every fare in the system was still priced on
    # crow-flight distance hours after the decision. A default that contradicts
    # the decision means the next fresh database silently reverts it, which is
    # the same failure a second time.
    #
    # Still a setting rather than a constant: if OSRM is unreachable the
    # resolver falls back to a straight line and SAYS SO on the row, and
    # switching back is one word in the console rather than a deploy.
    "routing_distance_source" => { type: :string, default: "osrm", description: "Where a fare's distance comes from: osrm (roads) or straight_line. Falls back to straight_line automatically when the router is unreachable, and records which was used." },
    # Above this the pin is not on the road network — Kabul is full of walled
    # compounds. Recorded, not corrected: the landmark note and the phone
    # number do the real work.
    "routing_snap_warning_metres" => { type: :decimal, default: "150.0", description: "Snap distance above which a pin is flagged as off the road network" },

    # Shown to a courier as their top-up instructions. Settings rather than
    # constants because the bank details will change and a courier stranded by
    # a stale account number cannot work.
    "wallet_low_balance_warning" => { type: :decimal, default: "200.0", currency: "AFN", description: "Warn a courier when available credit falls below this" },
    "top_up_bank_name"       => { type: :string, default: "", description: "Bank shown in a courier's top-up instructions" },
    "top_up_account_number"  => { type: :string, default: "", description: "Account number shown in a courier's top-up instructions" },

    "support_phone"          => { type: :string,  default: "", description: "Shown in all three apps. Delivery is an ops business with an app attached." },

    # THE OTP MESSAGE, per locale. Settings rather than Ruby constants for two
    # reasons: it is the first thing anybody ever reads from this platform, and
    # an SMS has no device to translate it — so unlike every other user-facing
    # string in the system the server must hold the words. Hamma9900 pastes the
    # real Pashto and Dari into the console with no deploy.
    #
    # The defaults are ENGLISH PLACEHOLDERS on purpose: a plausible-but-wrong
    # guess at Pashto ships unnoticed, and an obviously untranslated string
    # does not. `%{code}` is required and checked — a template pasted without
    # it would send a message containing no code.
    "otp_sms_body_ps"        => { type: :string, default: "Karwan: your code is %{code}", description: "OTP message, Pashto. AWAITING TRANSLATION. Must contain %{code}." },
    "otp_sms_body_fa"        => { type: :string, default: "Karwan: your code is %{code}", description: "OTP message, Dari. AWAITING TRANSLATION. Must contain %{code}." },
    "otp_sms_body_en"        => { type: :string, default: "Karwan: your code is %{code}", description: "OTP message, English. Must contain %{code}." },

    # Ride fares. Present so the numbers are tunable from day one, exactly like
    # the delivery fee — NOT because the ride product is built. Distance comes
    # from the straight line and eta_average_speed_kmh, not from a router.
    # THE FOUR `trip_*` FARE KEYS ARE GONE, to `pricing_rates`. They cannot live
    # in both places: a ride fare now depends on the vehicle class the passenger
    # chose, and two mechanisms would mean code deciding which to trust — the
    # exact reason the flat `delivery_fee` was replaced by a distance formula
    # rather than kept alongside it.
    #
    # `Setting` keeps the SCALARS. The commission rate is the same for every
    # class, so it stays here; the tariff varies by vehicle, so it is a row.
    # The rows for the retired keys are deleted by a migration, because a dead
    # price key on the Config screen is a number Hamma9900 would type and watch
    # do nothing.
    "trip_commission_rate"   => { type: :decimal, default: "0.125", description: "Platform share of a trip fare (0.125 = 12.5%). The tariff itself is in pricing_rates, per vehicle." }
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
