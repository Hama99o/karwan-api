module Merchants
  # Issues a shop's statement for a period, from the orders as they stand now.
  #
  # ── WHAT COUNTS ───────────────────────────────────────────────────────────
  #
  # DELIVERED orders only, by `delivered_at`. A cancelled or failed order
  # produced no sale and no commission, and an order placed on the last day of a
  # period but delivered in the next belongs to the period it was DELIVERED in —
  # that is when the courier handed over cash and the money actually moved.
  #
  # ── THE THREE AMOUNTS COME FROM THREE COLUMNS ─────────────────────────────
  #
  # `items_total`, `commission` and `merchant_payout` are each summed from their
  # own column on the order. `net_received` is NOT computed as sales minus
  # commission: a residual agrees with itself by construction and could never
  # disagree with the orders it describes, which is the one thing a statement
  # exists to let somebody check.
  #
  # ── IDEMPOTENT ────────────────────────────────────────────────────────────
  #
  # A weekly job retried, redeployed or re-run by hand must not hand a merchant
  # two statements for one week. The unique index is the guard; this rescues the
  # race rather than checking first and hoping.
  class IssueStatement
    def initialize(merchant, period_start:, period_end:, now: Time.current)
      @merchant = merchant
      @period_start = period_start.to_date
      @period_end = period_end.to_date
      @now = now
    end

    # Returns the statements written (one per currency), or the existing ones.
    def call
      totals_by_currency.map do |currency, totals|
        MerchantStatement.find_or_create_by!(
          merchant: @merchant, period_start: @period_start,
          period_end: @period_end, currency: currency
        ) do |statement|
          statement.orders_count = totals[:count]
          statement.items_total = totals[:items_total]
          statement.commission = totals[:commission]
          statement.net_received = totals[:net_received]
          statement.issued_at = @now
        end
      end
    rescue ActiveRecord::RecordNotUnique
      MerchantStatement.where(merchant: @merchant).for_period(@period_start, @period_end).to_a
    end

    private

    def delivered
      @merchant.orders.where(status: :delivered,
                             delivered_at: @period_start.beginning_of_day..@period_end.end_of_day)
    end

    # Grouped by currency and never summed across it — one-way door 2.
    def totals_by_currency
      counts = delivered.group(:currency).count
      items = delivered.group(:currency).sum(:items_total)
      commissions = delivered.group(:currency).sum(:commission)
      payouts = delivered.group(:currency).sum(:merchant_payout)

      counts.keys.index_with do |currency|
        { count: counts[currency], items_total: items[currency],
          commission: commissions[currency], net_received: payouts[currency] }
      end
    end
  end
end
