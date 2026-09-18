module Users
  # DELETING YOUR OWN ACCOUNT, WHICH THE APP STORES REQUIRE.
  #
  # Apple and Google both refuse an app that offers account creation without
  # in-app deletion, so this is compliance rather than a product choice. It is
  # still the most dangerous endpoint in the API, because the person pressing it
  # may be holding our cash.
  #
  # ── Shaped like Dispatch::Eligibility, on purpose ────────────────────────
  #
  # A boolean would tell a courier "no" and nothing else, and the whole point of
  # the refusal is that it is FIXABLE: settle up, then delete. So `reason`
  # names which check failed and the controller turns that into a sentence the
  # app can show. Same reason the dispatch gate names its refusals rather than
  # returning false — a person who is told only "no" concludes the app is
  # broken.
  #
  # ── What deletion IS here ────────────────────────────────────────────────
  #
  # `discard!`, never destroy. One-way door 6: a hard delete of somebody with
  # order history is a hole in the books, and every order already carries its
  # own `customer_phone` snapshot, so the history survives the row.
  class AccountDeletion
    REASONS = {
      holding_cash: "you are still holding cash for us — settle it first",
      wallet_unsettled: "your wallet has a balance to settle before you can close the account",
      live_job: "you have a job in progress — finish or hand it back first",
      live_order: "you have an order on its way — it must finish first",
      merchant_orders_in_flight: "your shop has orders in progress — they must finish first"
    }.freeze

    def initialize(user)
      @user = user
    end

    # nil when the account may be deleted, otherwise the symbol naming the
    # FIRST reason it may not. Money is checked before jobs, because money is
    # the door that does not swing back.
    def reason
      return :holding_cash if holding_cash?
      return :wallet_unsettled if wallet_unsettled?
      return :live_job if live_job?
      return :live_order if live_order?
      return :merchant_orders_in_flight if merchant_orders_in_flight?

      nil
    end

    def allowed?
      reason.nil?
    end

    def explanation
      REASONS[reason]
    end

    # Discards the account and revokes every session, so the phone in the
    # person's hand is signed out too rather than continuing on a token that
    # outlives the account.
    def call
      return false unless allowed?

      @user.transaction do
        @user.user_sessions.find_each(&:revoke!)
        @user.discard!

        # AUDITED WITH THE PERSON AS THE ACTOR, not an admin. One-way door 5
        # asks for an audit row on every intervention, and somebody closing
        # their own account is an intervention — it is simply one they made
        # themselves. Without this row, an operator restoring the account from
        # the console cannot tell a mistaken tap from a support request, and
        # the restore is audited while the deletion is not.
        AuditLog.record!(
          action: "user.account_closed", actor: @user, actor_role: :customer,
          target: @user,
          before: { deleted_at: nil },
          after: { deleted_at: @user.deleted_at.to_s },
          details: { sessions_revoked: @user.user_sessions.count, self_service: true }
        )
      end
      true
    end

    private

    # OUR money, in their pocket. A courier who has collected customer cash and
    # not settled it is the single case this endpoint exists to refuse.
    def holding_cash?
      return false if @user.courier_wallet.nil?

      Couriers::CashPosition.new(@user).held.positive?
    end

    # Either direction. A negative balance is money they owe us; a positive one
    # is prepaid credit we owe THEM, and closing the account over it would be
    # taking their money — which is worse than the first case, not better.
    def wallet_unsettled?
      wallet = @user.courier_wallet
      return false if wallet.nil?

      !wallet.balance.zero?
    end

    def live_job?
      @user.courier_orders.live.exists? || @user.courier_trips.live.exists?
    end

    def live_order?
      @user.orders.live.exists? || @user.trips.live.exists?
    end

    # A shop with orders in flight cannot lose its owner mid-delivery: the
    # merchant row survives, but nobody is left who can accept or reject.
    def merchant_orders_in_flight?
      Order.live.where(merchant_id: @user.owned_merchants.select(:id)).exists?
    end
  end
end
