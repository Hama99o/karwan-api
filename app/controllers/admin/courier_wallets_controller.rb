# The money interventions: record a top-up, adjust a balance, record a
# settlement.
#
# Every one goes through `CourierWallet#record_entry!`, so the balance and the
# ledger can never disagree — there is deliberately no path here that writes a
# balance directly.
module Admin
  class CourierWalletsController < Admin::ApplicationController
    # A bank deposit, reconciled from the statement by the courier's 4-digit
    # code rather than by name. Names repeat and transliterate badly
    # (Muhammad / Mohammad / Mohammed); a code survives a bank statement.
    def top_up
      wallet = requested_resource
      authorize wallet, :top_up?
      amount = params[:amount].to_d

      return reject_amount(wallet, "A top-up must be a positive amount.") unless amount.positive?

      entry = wallet.record_entry!(kind: :top_up, amount: amount, recorded_by_admin_user: current_admin_user, note: params[:note])
      log_intervention("wallet.topped_up", target: wallet,
                                           before: { balance: (wallet.balance - amount).to_s },
                                           after: { balance: wallet.balance.to_s },
                                           details: { amount: amount.to_s, top_up_code: wallet.top_up_code,
                                                      entry_id: entry.id, note: params[:note] })
      redirect_back fallback_location: admin_courier_wallet_path(wallet),
                    notice: "Credited #{amount} #{wallet.currency}."
    end

    # Either direction, and the reason is mandatory. An adjustment with no
    # explanation is indistinguishable from a mistake six months later.
    def adjust
      wallet = requested_resource
      authorize wallet, :adjust?
      amount = params[:amount].to_d
      note = params[:note].presence

      return reject_amount(wallet, "An adjustment needs a non-zero amount.") if amount.zero?
      return reject_amount(wallet, "An adjustment needs a reason.") if note.blank?

      entry = wallet.record_entry!(kind: :adjustment, amount: amount, recorded_by_admin_user: current_admin_user, note: note)
      # BOTH SIDES. "What was his balance before somebody adjusted it" is the
      # question this row exists to answer, and an `after` alone cannot answer
      # it — one-way door 5 asks for actor, action, BEFORE and after. This is
      # the most sensitive of the three movements: free-form, either
      # direction, and the only one whose amount a human invents.
      log_intervention("wallet.adjusted", target: wallet,
                                          before: { balance: (wallet.balance - amount).to_s },
                                          after: { balance: wallet.balance.to_s },
                                          details: { amount: amount.to_s, note: note, entry_id: entry.id })
      redirect_back fallback_location: admin_courier_wallet_path(wallet), notice: "Adjusted by #{amount}."
    end

    # Reimbursing a courier the platform's own loss — a refused order, a no-show,
    # a cancellation after pickup. A written policy, visible before their first
    # shift, and the same day.
    def reimburse
      wallet = requested_resource
      authorize wallet, :reimburse?
      amount = params[:amount].to_d

      return reject_amount(wallet, "A reimbursement must be a positive amount.") unless amount.positive?

      entry = wallet.record_entry!(kind: :reimbursement, amount: amount, recorded_by_admin_user: current_admin_user, note: params[:note])
      log_intervention("wallet.reimbursed", target: wallet,
                                            before: { balance: (wallet.balance - amount).to_s },
                                            after: { balance: wallet.balance.to_s },
                                            details: { amount: amount.to_s, note: params[:note],
                                                       entry_id: entry.id })
      redirect_back fallback_location: admin_courier_wallet_path(wallet),
                    notice: "Reimbursed #{amount} #{wallet.currency}."
    end

    # Counting the cash in.
    #
    # `expected` is COMPUTED from the unsettled jobs, never typed — the whole
    # value of this table is that the two numbers came from different places. A
    # typed expected figure could agree with the counted one by accident, which
    # is the single thing it exists to prevent.
    def settle
      wallet = requested_resource
      authorize wallet, :settle?
      counted = params[:counted_amount].to_d
      counter = params[:counted_by_name].presence

      return reject_amount(wallet, "Who counted it? A name is required.") if counter.blank?

      # ── WHAT THIS DEPOSIT COVERED ────────────────────────────────────────
      #
      # §4: they settle by BANK DEPOSIT, matched afterwards from the statement,
      # and keep working in between. Settling everything collected up to the
      # moment this is pressed recorded an honest courier as short by whatever
      # he earned after depositing, and forgot that he still held it. So the
      # operator gives the deposit's time; blank means now, as before.
      cutoff = deposit_cutoff
      return reject_amount(wallet, "That deposit time is in the future — check the statement.") if cutoff.nil?

      settlement = nil
      expected = nil
      ApplicationRecord.transaction do
        # ── ONE DEPOSIT, ONE SETTLEMENT ─────────────────────────────────────
        #
        # A second press of this button (a slow page, a double click, Back and
        # submit again) used to write a second Settlement over nothing:
        # expected 0, counted the same figure again, a variance of +counted.
        # Reproduced 2026-09-24 — a courier 200 short read as 120 short in
        # any sum of variances. Two presses AT ONCE were worse: both chose the
        # same jobs, and the shortfall was counted twice.
        #
        # So the set is chosen under the wallet's row lock, and a deposit
        # that covers nothing is refused — there is no work for it to settle,
        # and the likeliest reason is that it has just been recorded.
        wallet.lock!
        # The SAME set is summed and then marked, chosen once, so a delivery
        # completing while this runs cannot be marked settled without having
        # been expected.
        jobs = [ Order, Trip ].to_h { |klass| [ klass, covered_ids(klass, wallet.user, cutoff) ] }
        raise ActiveRecord::Rollback if jobs.values.all?(&:empty?)

        expected = jobs.sum(BigDecimal("0")) do |klass, ids|
          klass.where(id: ids, currency: wallet.currency).sum(:commission)
        end

        settlement = Settlement.create!(
          courier: wallet.user, expected_amount: expected, counted_amount: counted,
          currency: wallet.currency, counted_by_name: counter,
          settled_at: Time.current, period_end: cutoff, note: params[:note]
        )
        # Marking the jobs settled is what clears the cash-in-hand gate and
        # lets dispatch offer them work again.
        mark_settled(jobs)
      end

      if settlement.nil?
        return reject_amount(wallet, "Nothing collected up to that time is still unsettled — " \
                                     "if this deposit was just recorded, it is already under Settlements.")
      end

      log_intervention("courier.settled", target: settlement,
                                          details: { expected: expected.to_s, counted: counted.to_s,
                                                     variance: settlement.variance.to_s,
                                                     counted_by: counter })
      redirect_back fallback_location: admin_courier_wallet_path(wallet),
                    notice: "Settled. Expected #{expected}, counted #{counted}, variance #{settlement.variance}."
    end

    private

    def mark_settled(jobs)
      now = Time.current
      jobs.each do |klass, ids|
        klass.where(id: ids, payment_status: :collected)
             .update_all(payment_status: klass.payment_statuses[:settled], settled_at: now)
      end
    end

    # When the cash changed hands — ONE definition, shared with the "held
    # since" date the courier is warned from, so a settlement and a warning
    # cannot disagree about when money was collected.
    def covered_ids(klass, courier, cutoff)
      klass.for_courier(courier).where(payment_status: :collected)
           .where(Couriers::CashPosition::COLLECTED_AT.fetch(klass) => ..cutoff).pluck(:id)
    end

    # Read in `Time.zone` (Kabul): the statement's time is local. Nil for a
    # time in the future, which is a typo rather than a deposit.
    def deposit_cutoff
      raw = params[:deposited_at].presence
      return Time.current if raw.nil?

      at = Time.zone.parse(raw)
      at && at <= Time.current ? at : nil
    end

    def reject_amount(wallet, message)
      redirect_back fallback_location: admin_courier_wallet_path(wallet), alert: message
    end
  end
end
