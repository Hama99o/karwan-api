module Dispatch
  # Can this courier be offered this job, right now?
  #
  # One place, because the answer has four independent parts and scattering them
  # is how a courier ends up blocked for a reason nobody can name. Returns the
  # failing reason rather than a bare boolean, so admin can be told *why* a job
  # went unassigned — "no couriers available" is the least useful sentence in an
  # ops console.
  class Eligibility
    REASONS = {
      no_profile: "courier has no profile",
      not_approved: "courier is not approved",
      off_shift: "courier is not available",
      wrong_job_kind: "courier does not accept this kind of job",
      vehicle_too_small: "courier's vehicle cannot carry this order",
      too_many_passengers: "courier's vehicle does not seat this many people",
      wrong_vehicle_class: "passenger asked for a different kind of vehicle",
      already_on_a_job: "courier is already carrying a job",
      stale_location: "courier's last known position is too old to dispatch on",
      too_far: "courier is further from the pickup than dispatch will reach",
      no_wallet: "courier has no wallet",
      wallet_blocked: "courier's wallet is at or below its credit floor",
      insufficient_credit: "courier's wallet cannot cover this job",
      cash_in_hand: "courier is holding too much of our cash and must settle first"
    }.freeze

    def initialize(courier:, job:)
      @courier = courier
      @job = job
    end

    def eligible?
      reason.nil?
    end

    # nil when eligible, otherwise the symbol naming the first failure.
    def reason
      return :no_profile if profile.nil?
      return :not_approved unless profile.verification_approved?
      return :off_shift unless profile.is_available?
      return :wrong_job_kind unless profile.accepts?(@job.class.job_kind)
      # A BED AND A BOOK ARE NOT THE SAME DELIVERY.
      #
      # Without this a bulky order could be offered to a courier on a bicycle,
      # who would accept in good faith, ride there and find he cannot carry it
      # — a failure that costs the customer, the merchant and the courier at
      # once, and the only one of them who could have known is us.
      #
      # Costs NO QUERY: the requirement is snapshotted on the order row and the
      # capacity is a constant. Placed here, above the wallet, for the same
      # reason as the rest — cheapest first, and this is free.
      #
      # A ride has no size, so this only ever asks an Order.
      return :vehicle_too_small unless vehicle_big_enough?
      # A PASSENGER WHO PAID FOR A CAR MUST NOT BE COLLECTED ON A MOTORBIKE.
      #
      # The class is part of what was agreed — it is why the fare could depend
      # on the vehicle and still be quoted upfront — so dispatch matches it
      # exactly rather than treating a bigger vehicle as a free upgrade. A car
      # driver taking a motorbike fare would earn motorbike money and decline
      # anyway; offering it wastes the offer's TTL, which the customer pays for
      # in waiting.
      return :wrong_vehicle_class unless vehicle_class_matches?
      # And it must actually seat them. Without this a family of four could
      # agree a fare and be undispatchable — the same failure as a bed on a
      # bicycle, on a people axis.
      return :too_many_passengers unless enough_seats?
      # ONE LIVE JOB PER COURIER, ACROSS BOTH DEMAND TYPES.
      #
      # This check did not exist, and its absence meant a courier riding to a
      # customer with a meal in his box could be offered a TRIP and accept it.
      # Nothing refused him. One human, two jobs, two places — and one of those
      # customers loses for certain: either the food goes cold while he drives
      # a passenger across Kabul, or a passenger waits at a kerb while he
      # finishes the delivery.
      #
      # It has to span BOTH tables, which is why it is here rather than on
      # either job class: the whole utilisation thesis is one pool serving two
      # demand streams, so "already busy" is only true if you look at both.
      #
      # GUARD THE JOB, NOT THE DEVICE. Once this holds server-side, how many
      # phones a courier carries stops mattering — and it must stop mattering,
      # because swapping to a second phone mid-shift when the first one dies is
      # a real thing on a cheap Android in Kabul.
      #
      # Placed above the wallet checks deliberately: it is the cheapest query
      # here and the most common reason to skip a courier on a busy evening, so
      # the dispatcher should reach it before touching the ledger.
      return :already_on_a_job if carrying_another_job?
      # Dispatch is distance-based, so a fix we cannot trust is a dispatch we
      # cannot make. Better to skip this courier than to send the nearest
      # courier-shaped memory.
      return :stale_location unless profile.location_fresh?
      # ── AND A CEILING ON HOW FAR WE WILL ASK ───────────────────────────────
      #
      # `OfferService` picks the NEAREST eligible courier, which silently means
      # "however far away he is". In one neighbourhood that is harmless and this
      # check never fires. The day a second city exists it stops being harmless:
      # a Kabul order would be offered to a Jalalabad courier, who accepts in
      # good faith and then rides 150km or cancels — and the only party who
      # could have known is us.
      #
      # ORDERED AFTER `stale_location` DELIBERATELY. A distance computed from a
      # position we do not trust is worse than no distance at all, so freshness
      # has to be established first; reversing these two would reject couriers
      # on the strength of where they were an hour ago.
      #
      # ── THE TRADE-OFF, because this runs at ACCEPT too ─────────────────────
      #
      # `Eligibility` is re-checked when a courier taps accept, so in principle
      # someone offered a job at 7.9km who drifts to 8.1km is refused a job we
      # already decided to give him — us changing our mind. Accepted, for two
      # reasons: nobody crosses that distance inside a 60-second offer TTL, and
      # if he genuinely IS too far then riding there is the outcome this exists
      # to prevent. The alternative — checking only when offering — would put
      # this rule outside the one class that can name why a courier was skipped,
      # which is the scattering this file's own header warns about.
      return :too_far if too_far?
      return :no_wallet if wallet.nil?
      return :wallet_blocked if wallet.blocked?
      return :insufficient_credit unless wallet.can_fund?(@job)
      return :cash_in_hand if cash_position.over_limit?

      nil
    end

    def explanation
      REASONS[reason]
    end

    private

    # Straight-line, because that is what a ceiling needs: it excludes the
    # absurd rather than ranking the plausible, and `OfferService` already
    # orders candidates by the same measure.
    #
    # FAILS OPEN on a missing coordinate, and that is the safe direction here.
    # A job with no pickup point cannot be dispatched at all — `OfferService`
    # returns early on exactly that — so answering "too far" would put a
    # misleading reason on the admin board for a job whose real problem is a
    # missing address.
    def too_far?
      pickup = @job.pickup_coordinates
      here = profile.coordinates
      return false if pickup.nil? || here.nil?

      distance = Geo::Distance.km(
        from_lat: here[0], from_lng: here[1],
        to_lat: pickup[0], to_lng: pickup[1]
      )
      return false if distance.nil?

      distance > Setting.fetch("dispatch_max_offer_radius_km")
    end

    def profile
      @profile ||= @courier.courier_profile
    end

    # Only a ride has a class and a passenger count; a delivery has neither, so
    # both questions answer yes for an Order without asking anything.
    def vehicle_class_matches?
      requested = @job.try(:vehicle_type)
      # Nil means the passenger chose nothing — trips booked before classes
      # existed, or a future path that does not ask. Any vehicle will do.
      return true if requested.blank?

      requested.to_s == profile.vehicle_type.to_s
    end

    def enough_seats?
      count = @job.try(:passenger_count)
      return true if count.blank?

      profile.seats?(count)
    end

    # Rides are people, not goods, so there is nothing to fit.
    def vehicle_big_enough?
      return true unless @job.respond_to?(:required_size_class)

      profile.carries?(@job.required_size_class)
    end

    # Any live job assigned to this courier, other than the one being offered.
    #
    # The job itself is excluded so a RE-OFFER of work he already holds is not
    # refused as a conflict — that would make an admin reassignment of the same
    # job to the same courier impossible to explain.
    def carrying_another_job?
      [ Order, Trip ].any? do |klass|
        scope = klass.live.for_courier(@courier)
        scope = scope.where.not(id: @job.id) if @job.is_a?(klass)
        scope.exists?
      end
    end

    def wallet
      @wallet ||= @courier.courier_wallet
    end

    def cash_position
      @cash_position ||= Couriers::CashPosition.new(@courier)
    end
  end
end
