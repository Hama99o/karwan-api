module Couriers
  # Performs the courier's current step.
  #
  # The courier app sends "I did the thing in front of me" rather than naming a
  # status, and the server decides what that means. That asymmetry is
  # deliberate: a client that names the transition can name the wrong one, and
  # correction 7's five-buttons-five-transitions only holds if the server owns
  # the mapping.
  #
  # THE MONEY MOVES HERE, atomically with the transition. A job marked
  # delivered without its commission charged, or a commission charged against a
  # job that did not move, are both states nobody can reconcile.
  class AdvanceJobService
    Error = Class.new(StandardError)
    NotYourJob = Class.new(Error)
    NothingToDo = Class.new(Error)
    WrongStep = Class.new(Error)

    def initialize(job:, courier:, step_key: nil)
      @job = job
      @courier = courier
      @step_key = step_key
    end

    def call
      raise NotYourJob, "this job is not assigned to you" unless @job.courier_id == @courier.id

      step = current_step
      raise NothingToDo, "there is nothing left to do on this job" if step.nil?
      # An explicit step key is optional, but when the app sends one it must
      # match — otherwise a stale screen advances a step the courier is not
      # actually standing at.
      raise WrongStep, "the current step is #{step[:key]}" if @step_key.present? && @step_key.to_s != step[:key]

      ApplicationRecord.transaction do
        @job.transition_to!(step[:status_after], actor: @courier, actor_role: :courier) ||
          raise(Error, "cannot move this job from #{@job.status}")

        apply_money(step)
        @job
      end
    end

    private

    # The first step that has an ACTION and is not yet done.
    #
    # Deliberately not "the step marked current": a navigation step can be
    # current for display purposes while carrying no transition, and requiring
    # both made every job unadvanceable at step one.
    def current_step
      JobSteps.new(@job).call.find { |step| step[:status_after].present? && !step[:completed] }
    end

    def apply_money(step)
      case step[:key]
      when "pay_merchant"
        # The courier has handed over their own money. Recorded so a dispute at
        # the counter has a timestamp, and so the admin board can tell "paid but
        # not delivered" from "not yet collected".
        @job.update!(merchant_paid_at: Time.current)
      when "collect_and_deliver", "complete_and_collect"
        collect!
      end
    end

    # Cash is now in the courier's hand, and our commission is owed from their
    # prepaid wallet. One ledger entry, written at the moment it happens —
    # one-way door #4: a balance can be recomputed from entries, entries can
    # never be reconstructed from a balance.
    def collect!
      @job.update!(payment_status: :collected)

      wallet = @courier.courier_wallet
      return if wallet.nil?
      # Idempotent against a double-tap on a bad connection: the commission for
      # this job is charged once or not at all.
      return if wallet.wallet_entries.exists?(source: @job, kind: :commission)

      wallet.record_entry!(
        kind: :commission, amount: -@job.commission, source: @job,
        recorded_by: @courier, note: "Commission on #{@job.code}"
      )

      record_topup!(wallet)
    end

    # WHAT WE GAVE BACK, as its own movement rather than as a smaller
    # commission. One-way door #4: a balance can be recomputed from entries and
    # entries can never be reconstructed from a balance — a top-up that showed
    # only as a reduced commission would be a movement with no record, and
    # "what did the top-up cost us in November" would be unanswerable.
    #
    # It also keeps `merchant_payout` still: that figure is derived from
    # `commission`, so reducing the commission itself would quietly pay the
    # RESTAURANT more, on exactly the thin far orders this exists to rescue.
    #
    # THE NOTE IS FOR AN OPERATOR, not for the courier. There is no wallet
    # screen in the app — `/courier/wallet/entries` has no client caller yet —
    # so this is read in the ops console, where a complaint is actually
    # answered. It carries the arithmetic rather than a sentence, so the figure
    # explains itself. Courier-facing copy gets written in Pashto when the
    # statement screen is built, by somebody looking at the screen.
    def record_topup!(wallet)
      topup = @job.try(:commission_topup).to_d
      return if topup <= 0
      return if wallet.wallet_entries.exists?(source: @job, kind: :commission_topup)

      wallet.record_entry!(
        kind: :commission_topup, amount: topup, source: @job,
        recorded_by: @courier,
        note: "Distance top-up on #{@job.code}: #{@job.distance_km}km drop, " \
              "min #{Setting.fetch('courier_min_earnings_per_km')}/km"
      )
    end
  end
end
