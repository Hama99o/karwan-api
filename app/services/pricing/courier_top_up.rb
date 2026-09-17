module Pricing
  # THE DEAD LEG NOBODY WAS PAYING FOR.
  #
  # Hamma9900's case, in his words: a cheap order a long way out — *"we will
  # have a zero commission for our side."* Today the delivery fee is priced on
  # the merchant→customer distance alone, so a 200 AFN order 6 km away pays the
  # courier for the short hop at the end and nothing at all for the ride OUT to
  # the restaurant. He takes it once, discovers what it cost him, and declines
  # the next one — and the orders that go undelivered are exactly the ones on
  # the edge of the neighbourhood we most need covered.
  #
  # So: if what the courier earns falls short of what the distance he actually
  # rides is worth, **top it up out of our commission, down to zero and never
  # below.** We give up margin on a thin far order rather than lose the courier
  # or the customer. Off by default; `courier_min_earnings_per_km` is his
  # number to set.
  #
  # ── WHY THIS IS NOT IN `DeliveryQuote` ────────────────────────────────────
  #
  # The dead leg is courier→merchant, and **at quote time there is no
  # courier.** The quote runs at the cart, before the order exists, let alone
  # an offer. So this runs at ASSIGNMENT, where both ends of that leg finally
  # exist.
  #
  # That turns out to be free rather than a compromise: the top-up moves money
  # from our commission to the courier and **changes nothing the customer was
  # quoted**, so correction 13's freeze on every customer-facing amount is
  # untouched. Nothing here reads or writes `merchant_payout` either — the
  # restaurant is not part of this transaction.
  #
  # ── WHY IT TAKES A SET OF JOBS ────────────────────────────────────────────
  #
  # Correction 19: batching is next, and batched, two jobs SHARE one dead leg.
  # Paid per job, a shared leg would be paid for twice — the platform funding a
  # ride nobody took. The arithmetic here sums one dead leg and each drop
  # separately, so a batch is priced as the journey it actually is. Call sites
  # pass one job today, which is the same shape `can_fund?(*jobs)` already
  # uses.
  #
  # DELIVERIES ONLY. A ride's fare already carries its own distance and the
  # courier advances nothing, so there is no dead leg being silently absorbed.
  # If rides ever need this, the shape is here and the name of the earnings
  # field is the only thing that differs.
  module CourierTopUp
    ZERO = BigDecimal("0")

    # What each job's commission should be reduced by, as {job => amount}.
    # Empty when the switch is off, when nothing is short, or when there is no
    # position to measure from — this must never be the reason an assignment
    # fails.
    def self.for(courier:, jobs:)
      jobs = Array(jobs).compact
      return {} if jobs.empty? || !Setting.fetch("courier_topup_enabled")

      shortfall = shortfall_for(courier: courier, jobs: jobs)
      return {} if shortfall <= ZERO

      allocate(shortfall, jobs)
    end

    # What the whole run is short, before it is capped by what we actually have
    # to give.
    def self.shortfall_for(courier:, jobs:)
      km = total_km(courier: courier, jobs: jobs)
      return ZERO if km.nil? || km <= ZERO

      required = Setting.fetch("courier_min_earnings_per_km") * km
      earned = jobs.sum { |job| job.courier_fee.to_d }

      [ required - earned, ZERO ].max
    end

    # ONE dead leg plus every drop. The dead leg is measured to the FIRST
    # pickup only: a courier rides out once, whatever he collects when he gets
    # there.
    #
    # Straight-line for the dead leg, deliberately, even though the drops are
    # priced on roads. It decides whether to give money away and does not have
    # to be exact — and a routing call on the accept path is a network round
    # trip inside a transaction holding a lock on the courier's row.
    def self.total_km(courier:, jobs:)
      drops = jobs.sum { |job| job.distance_km.to_d }
      leg = dead_leg_km(courier: courier, jobs: jobs)
      return nil if leg.nil?

      drops + leg
    end

    def self.dead_leg_km(courier:, jobs:)
      here = courier.courier_profile&.coordinates
      pickup = jobs.filter_map(&:pickup_coordinates).first
      return nil if here.nil? || pickup.nil?

      km = Geo::Distance.km(from_lat: here[0], from_lng: here[1],
                            to_lat: pickup[0], to_lng: pickup[1])
      km&.to_d
    end

    # Split across the jobs, each capped by its OWN commission — that is what
    # "out of the platform's commission, never below zero" means per order, and
    # a batch must not fund one job's shortfall out of another's margin.
    #
    # Largest remainder, so the parts sum to exactly the whole. Money split by
    # rounding each share independently is the classic way to lose or invent a
    # minor unit, and `Monetary` already refuses a record whose parts miss the
    # total.
    def self.allocate(shortfall, jobs)
      capacity = jobs.to_h { |job| [ job, job.commission.to_d ] }
      total_capacity = capacity.values.sum
      return {} if total_capacity <= ZERO

      payable = [ shortfall, total_capacity ].min
      shares = capacity.transform_values { |cap| (payable * cap / total_capacity).round(2) }

      distribute_remainder(shares, capacity, payable)
      shares.reject { |_job, amount| amount <= ZERO }
    end

    # Pushes the rounding residue onto the jobs with the most room, one minor
    # unit at a time, so no job is ever credited more commission than it has.
    #
    # BOUNDED BY CONSTRUCTION rather than by the residue reaching zero. This
    # runs inside the accept transaction, which holds a lock on the courier's
    # row — a loop that can fail to terminate there does not merely hang a
    # request, it holds that lock until something kills the connection, and
    # every other accept by that courier queues behind it. A residue no job has
    # room for is possible (every share already at its own cap), so "keep going
    # until it is distributed" is exactly the condition that cannot be
    # guaranteed. One pass per minor unit, and it stops when a whole pass moves
    # nothing.
    def self.distribute_remainder(shares, capacity, payable)
      residue = payable - shares.values.sum
      return if residue.zero?

      step = residue.negative? ? BigDecimal("-0.01") : BigDecimal("0.01")
      order = capacity.keys.sort_by { |job| -capacity[job] }

      until residue.zero?
        moved = false

        order.each do |job|
          break if residue.zero?

          nudged = shares[job] + step
          next if nudged > capacity[job] || nudged.negative?

          shares[job] = nudged
          residue -= step
          moved = true
        end

        # Nothing could take it. Better a minor unit undistributed than a
        # request that never returns.
        break unless moved
      end
    end

    private_class_method :allocate, :distribute_remainder
  end
end
