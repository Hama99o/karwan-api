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

    def wallet
      @wallet ||= @courier.courier_wallet
    end

    def cash_position
      @cash_position ||= Couriers::CashPosition.new(@courier)
    end
  end
end
