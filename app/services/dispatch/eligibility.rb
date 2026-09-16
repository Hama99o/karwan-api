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
      already_on_a_job: "courier is already carrying a job",
      stale_location: "courier's last known position is too old to dispatch on",
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

    def profile
      @profile ||= @courier.courier_profile
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
