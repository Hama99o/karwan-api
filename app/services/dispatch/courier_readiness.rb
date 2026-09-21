module Dispatch
  # ── WHY IS MY PHONE QUIET? ────────────────────────────────────────────────
  #
  # `Eligibility` names fourteen reasons a courier is skipped, and the courier
  # is told none of them. The shift payload carries the raw facts — wallet,
  # cash in hand, location freshness — and its own comment says they are
  # *"shown rather than discovered when dispatch goes quiet"*. But facts are not
  # an answer: to turn them into one the phone must reimplement the dispatcher,
  # and then the phone can disagree with it.
  #
  # That is the same argument `Couriers::JobSteps` makes about the step list:
  # *"deciding which here rather than on the device means the phone cannot
  # disagree with the server about what happens next."* CLAUDE.md calls courier
  # supply the scarce side, and a courier sitting on a kerb wondering why
  # nothing comes is the one who stops turning up.
  #
  # ── EIGHT OF THE FOURTEEN, AND ONLY EIGHT ─────────────────────────────────
  #
  # Six reasons are about a PAIRING — wrong job kind, vehicle too small, wrong
  # vehicle class, too many passengers, too far, insufficient credit for THIS
  # job. None can be answered without a job in hand, so a shift screen cannot
  # honestly speak to them.
  #
  # The other eight are about the courier alone and are answerable at any
  # moment. Those are what this returns.
  #
  # ── SO IT MAKES A NEGATIVE CLAIM, DELIBERATELY ────────────────────────────
  #
  # Nil does NOT mean "you will get work". It means **nothing about you is
  # blocking you** — the six pairing reasons are still live, and so is the
  # plainest one of all, that nobody has ordered anything. A field promising
  # work would be the same species of lie as a card reading "open now, opens at
  # 08:00": provable-sounding and unprovable.
  #
  # ── ONE VOCABULARY ────────────────────────────────────────────────────────
  #
  # Every symbol returned here is a key of `Eligibility::REASONS`, asserted in
  # the spec. A second list of words for one concept is how `merchant_owner`
  # and `merchant` happened.
  class CourierReadiness
    # The courier-only reasons, in the order `Eligibility` would meet them, so
    # the courier is told the same FIRST reason the dispatcher would hit rather
    # than a different true one.
    ORDER = %i[account_suspended no_profile not_approved off_shift already_on_a_job
               stale_location no_wallet wallet_blocked cash_in_hand].freeze

    def initialize(courier)
      @courier = courier
    end

    # The first courier-only reason, or nil when none of them applies.
    def blocked_by
      # First, as in `Eligibility`. The ordering spec demands the two agree, so
      # a reason added to one and not the other turns it red.
      return :account_suspended unless @courier.account_active?
      return :no_profile if profile.nil?
      return :not_approved unless profile.verification_approved?
      return :off_shift unless profile.is_available?
      return :already_on_a_job if carrying_a_job?
      return :stale_location unless profile.location_fresh?
      return :no_wallet if wallet.nil?
      return :wallet_blocked if wallet.blocked?
      return :cash_in_hand if cash_position.over_limit?

      nil
    end

    private

    # ANY live job, with none to exclude. `Eligibility` excludes the job being
    # offered, because re-offering work a courier already holds must not read as
    # a conflict. There is no such job here — the question is "are you carrying
    # anything", so the exclusion would have nothing to exclude and its absence
    # is the correct difference rather than a divergence.
    def carrying_a_job?
      [ Order, Trip ].any? { |klass| klass.live.for_courier(@courier).exists? }
    end

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
