module Couriers
  # The courier's wallet, as they see it.
  #
  # PRODUCT.md: balance, credit line, recent entries, and **top-up
  # instructions showing their own 4-digit reference code**. Warn clearly as the
  # balance nears zero, because at zero they stop earning — so the warning is a
  # field the server computes rather than a threshold the app guesses.
  class WalletSerializer < ApplicationSerializer
    identifier :id

    fields :balance, :credit_line, :currency, :top_up_code

    # How far below zero they may go. Stored positive, applied negative — the
    # app should never have to work that out.
    field :floor do |wallet|
      wallet.floor
    end

    field :available_credit do |wallet|
      wallet.available_credit
    end

    field :blocked do |wallet|
      wallet.blocked?
    end

    # Computed here, not on the device. A client deciding its own warning
    # threshold would drift from the one dispatch actually enforces.
    field :low_balance do |wallet|
      wallet.available_credit <= Setting.fetch("wallet_low_balance_warning")
    end

    # Money of ours they are holding, and how much more they may collect before
    # settling. Shown rather than discovered when dispatch goes quiet.
    field :cash_in_hand do |wallet|
      CashPosition.new(wallet.user).held
    end

    field :cash_allowance_remaining do |wallet|
      CashPosition.new(wallet.user).remaining_allowance
    end

    field :must_settle do |wallet|
      CashPosition.new(wallet.user).over_limit?
    end

    view :detailed do
      # The instructions themselves are i18n KEYS plus the values they need —
      # the server does not know how to explain a bank deposit in Pashto, and a
      # server-written English sentence is untranslatable on the device.
      field :top_up_instructions do |wallet|
        {
          message_key: "courier.wallet.top_up_instructions",
          reference_code: wallet.top_up_code,
          bank_name: Setting.fetch("top_up_bank_name"),
          account_number: Setting.fetch("top_up_account_number"),
          support_phone: Setting.fetch("support_phone")
        }
      end

      # Today, per PRODUCT.md: deliveries, earnings, cash in hand.
      field :today do |wallet|
        courier = wallet.user
        since = Time.zone.now.beginning_of_day
        deliveries = Order.for_courier(courier).where(status: :delivered, delivered_at: since..)
        rides = Trip.for_courier(courier).where(status: :completed, completed_at: since..)

        {
          deliveries: deliveries.count,
          rides: rides.count,
          # Grouped by currency, never summed across it.
          earnings: merge_by_currency(
            deliveries.group(:currency).sum(:courier_fee),
            rides.group(:currency).sum(:courier_earnings)
          ),
          commission_charged: merge_by_currency(
            deliveries.group(:currency).sum(:commission),
            rides.group(:currency).sum(:commission)
          )
        }
      end
    end

    def self.merge_by_currency(first, second)
      first.merge(second) { |_currency, a, b| a + b }
    end
  end
end
