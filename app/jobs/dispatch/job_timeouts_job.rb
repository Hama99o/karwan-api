module Dispatch
  # Acts on jobs that have sat in one state too long.
  #
  # CLAUDE.md: "Every state needs: who can move it, a timeout, and what happens
  # on timeout. An order stuck with no timeout is a person waiting with cold
  # food." The timeouts were declared in `Order::TIMEOUTS` and `Trip::TIMEOUTS`
  # and `#overdue?` read them, but nothing acted on them.
  #
  # WHAT HAPPENS ON TIMEOUT IS DELIBERATELY DIFFERENT PER STATE, and the line is
  # whether anyone is out of pocket yet:
  #
  #   placed / requested — nobody has cooked anything and no money has moved, so
  #     the system closes it and the customer is TOLD. Leaving it open is worse:
  #     they sit watching a screen, and the merchant that never answered is not
  #     going to start now.
  #
  #   everything after that — food exists, or a courier is en route, or cash has
  #     changed hands. A machine must not cancel that. It is flagged for a human,
  #     who can telephone the merchant, reassign the courier, or refund. Support
  #     is a person, and the brief says so.
  class JobTimeoutsJob < ApplicationJob
    queue_as :default

    # The states a machine may close by itself: nothing has been committed.
    SELF_CLOSING = {
      # `no_answer`, NOT `closing`. The job used to write the reason a shop gives
      # when it shuts early, about shops that said nothing at all — so a column
      # meaning "the merchant's stated reason" carried a sentence no merchant
      # had uttered, and every reader downstream had to know that.
      "Order" => { state: :placed, to: :rejected, reason: :no_answer },
      "Trip"  => { state: :requested, to: :cancelled, reason: :no_courier_available }
    }.freeze

    def perform
      closed = 0
      flagged = 0

      [ Order, Trip ].each do |klass|
        klass.live.overdue.find_each do |job|
          if self_closing?(job)
            closed += 1 if close!(job)
          else
            flag!(job)
            flagged += 1
          end
        end
      end

      { closed: closed, flagged: flagged }
    end

    private

    def rule_for(job)
      SELF_CLOSING[job.class.name]
    end

    def self_closing?(job)
      rule_for(job)&.fetch(:state).to_s == job.status
    end

    def close!(job)
      rule = rule_for(job)

      # Actor is nil — the system did this, not a person. That distinction is
      # the difference between "the merchant rejected it" and "the merchant
      # never answered", and support needs to tell them apart.
      moved = job.transition_to!(rule[:to], actor: nil, actor_role: :admin,
                                            reason: "timed out in #{job.status} with no response")
      return false unless moved

      job.update(reason_column(job) => rule[:reason])
      AuditLog.record!(action: "#{job.class.name.downcase}.timed_out", actor: nil, target: job,
                       before: { status: rule[:state].to_s }, after: { status: rule[:to].to_s },
                       details: { note: "closed automatically; nothing had been committed" })
      true
    end

    def reason_column(job)
      job.is_a?(Order) ? :rejection_reason : :cancellation_reason
    end

    # Flagged, not moved. An audit row is what surfaces it on the admin board
    # without a machine making a decision that costs somebody money.
    #
    # ── ONCE PER STUCK STATE, NOT ONCE A MINUTE ───────────────────────────
    #
    # This job runs every minute, and this used to write a row on every run
    # for every job still past its timeout — 784 of 935 audit rows on the dev
    # database, and ~180 for one order stuck three hours in production. The
    # audit log is where a human looks for who reassigned, cancelled or
    # credited; the machine's repeats buried them. The board itself reads the
    # `overdue` SQL scope, not these rows, so nothing is lost by writing one.
    #
    # "Already flagged" is THIS job, since it ENTERED its current state. The
    # same job stuck again after moving on is a new fact and is flagged again.
    # The window alone does that — no status comparison as well: states never
    # re-enter today, so a second condition could not remove a row the first
    # had kept, and a check that cannot fail is worse than none. The window is
    # also the one that stays right if a job ever could re-enter a state.
    def flag!(job)
      return if already_flagged?(job)

      AuditLog.record!(
        action: "#{job.class.name.downcase}.overdue", actor: nil, target: job,
        details: {
          status: job.status,
          minutes_in_state: ((Time.current - job.state_entered_at) / 60).round,
          note: "needs a human: money or goods are already committed"
        }
      )
    end

    def already_flagged?(job)
      AuditLog.where(action: "#{job.class.name.downcase}.overdue", target: job,
                     created_at: job.state_entered_at..).exists?
    end
  end
end
