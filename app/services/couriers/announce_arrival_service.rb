module Couriers
  # "I AM AT THE GATE." One action, two demand types, different mechanics.
  #
  # A RIDE already had a state for this — `arrived` — because a passenger who
  # is not at the kerb is the whole problem of a taxi, and the state machine
  # owns that transition.
  #
  # A DELIVERY has no such state and does not need one: nothing expires
  # because of arrival, nobody else acts on it, and the order is `picked_up`
  # either way. It records a timestamp instead. See the migration for why that
  # is not a shortcut.
  #
  # ── IDEMPOTENT, BECAUSE A THUMB IS NOT A TRANSACTION ──────────────────────
  # A courier taps with one hand, in sunlight, wearing a glove. A second tap —
  # or a retry after a bad connection — must not ring the customer again. The
  # first announcement wins and the rest are silent successes.
  class AnnounceArrivalService
    Error = Class.new(StandardError)
    NotYourJob = Class.new(Error)
    TooEarly = Class.new(Error)

    def initialize(job:, courier:)
      @job = job
      @courier = courier
    end

    # Returns true when this call is the one that announced it, false when it
    # had already been announced. Both are successes to the caller.
    def call
      raise NotYourJob, "this job is not assigned to you" unless @job.courier_id == @courier.id

      return false if already_announced?

      # Announcing arrival before collecting the food would tell a customer to
      # come down to nobody. For a ride there is nothing to collect, so the
      # only requirement is that the trip is live.
      raise TooEarly, "this job has not started yet" unless under_way?

      announce!
      true
    end

    private

    def already_announced?
      @job.is_a?(Trip) ? @job.arrived_at.present? : @job.courier_arrived_at.present?
    end

    def under_way?
      # No enum prefix on either job's status, so these read as the states
      # themselves — which is how the rest of the codebase asks.
      @job.is_a?(Trip) ? @job.accepted? || @job.arrived? : @job.picked_up?
    end

    def announce!
      ApplicationRecord.transaction do
        if @job.is_a?(Trip)
          # THROUGH THE STATE MACHINE, which owns the transition, records the
          # actor and writes the timestamp. A bare `update!` here would leave
          # the trip's history with a gap exactly where somebody would look.
          @job.transition_to!(:arrived, actor: @courier, actor_role: :courier)
        else
          @job.update!(courier_arrived_at: Time.current)
        end

        # Enqueued inside the transaction so it cannot fire for an arrival that
        # failed to save; ActiveJob delivers after commit.
        Notifications::ArrivalAlertJob.perform_later(@job.class.name, @job.id)
      end
    end
  end
end
