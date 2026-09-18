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

      position = Couriers::CashPosition.new(wallet.user)
      expected = position.held

      settlement = nil
      ApplicationRecord.transaction do
        settlement = Settlement.create!(
          courier: wallet.user, expected_amount: expected, counted_amount: counted,
          currency: wallet.currency, counted_by_name: counter,
          settled_at: Time.current, note: params[:note]
        )
        # Marking the jobs settled is what clears the cash-in-hand gate and
        # lets dispatch offer them work again.
        mark_settled(wallet.user)
      end

      log_intervention("courier.settled", target: settlement,
                                          details: { expected: expected.to_s, counted: counted.to_s,
                                                     variance: settlement.variance.to_s,
                                                     counted_by: counter })
      redirect_back fallback_location: admin_courier_wallet_path(wallet),
                    notice: "Settled. Expected #{expected}, counted #{counted}, variance #{settlement.variance}."
    end

    private

    def mark_settled(courier)
      now = Time.current
      [ Order, Trip ].each do |klass|
        klass.for_courier(courier).where(payment_status: :collected)
             .update_all(payment_status: klass.payment_statuses[:settled], settled_at: now)
      end
    end

    def reject_amount(wallet, message)
      redirect_back fallback_location: admin_courier_wallet_path(wallet), alert: message
    end
  end
end
