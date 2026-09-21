module Merchants
  # ── THE "TODAY" SCREEN, WHICH HAD NO ENDPOINT ─────────────────────────────
  #
  # `PRODUCT.md`'s Restaurant section names five screens. Four are built; this
  # is the fifth, specified in one line — *"**Today** — orders, items sold, cash
  # received from riders, our commission. No charts."* — and served by nothing.
  #
  # ── THE SAME ARITHMETIC AS THE WEEKLY STATEMENT, DELIBERATELY ─────────────
  #
  # `Merchants::IssueStatement` counts DELIVERED orders by `delivered_at`, sums
  # `items_total`, `commission` and `merchant_payout` each from its own column,
  # and groups by currency. This does the same over one day.
  #
  # That is the whole design constraint. A shop that reads 5,000 here on Friday
  # and a statement that says something else for the same week stops believing
  # both, and the statement is the one that matters — it is the financial record
  # already shown to a partner. Two computations of one figure is how two
  # screens come to disagree, which this repo has now paid for four times.
  #
  # **`net_received` is summed, never derived.** The statement's own reason:
  # *"a residual agrees with itself by construction and could never disagree
  # with the orders it describes, which is the one thing a statement exists to
  # let somebody check."* Same here — if the columns ever disagree, this must be
  # able to show it.
  #
  # ── WHY DELIVERED AND NOT PICKED UP, WHICH IS NOT OBVIOUS ─────────────────
  #
  # Under Model A the courier hands the shop its cash at PICKUP, so "cash
  # received from riders" is arguably `merchant_paid_at`. It is not, and §5 is
  # why: when food comes back, *"the restaurant refunds him his advance and pays
  # his fee"*. A picked-up order is money the shop is holding and may have to
  # hand straight back, so counting it as received would overstate a day that a
  # single refusal reverses. Delivered is the point at which the shop keeps it.
  #
  # `in_the_kitchen` carries the difference rather than hiding it — a shopkeeper
  # comparing this screen to the cash in the drawer needs to know what is still
  # out on the road.
  class TodaysTrade
    def initialize(merchant, now: Time.current)
      @merchant = merchant
      @now = now
    end

    # One entry per currency, never summed across them — one-way door 2. A
    # single currency today, which is exactly when the habit is cheap.
    def call
      {
        # THE DAY IS KABUL'S. `config.time_zone` is Kabul, so `all_day` on a
        # zoned time already cuts the day where the shopkeeper lives. The
        # reports page had to say this in SQL because it GROUPS by day; one
        # day's range does not.
        from: day.begin,
        to: day.end,
        by_currency: totals_by_currency,
        in_the_kitchen: live_orders_count
      }
    end

    private

    def day = @now.in_time_zone.all_day

    def delivered
      @delivered ||= @merchant.orders.where(status: :delivered, delivered_at: day)
    end

    # Orders the shop has taken on and not finished: what the drawer is still
    # waiting for. `live` excludes every terminal state, so a rejected order is
    # not counted as outstanding work.
    def live_orders_count
      @merchant.orders.live.count
    end

    def totals_by_currency
      counts = delivered.group(:currency).count
      items = delivered.group(:currency).sum(:items_total)
      commissions = delivered.group(:currency).sum(:commission)
      payouts = delivered.group(:currency).sum(:merchant_payout)
      # Summed from the LINES, not from the orders — "items sold" is a count of
      # food, and an order of three kebabs is three.
      quantities = OrderItem.where(order: delivered).group(:currency).sum(:quantity)

      counts.keys.index_with do |currency|
        {
          currency: currency,
          orders: counts[currency],
          items_sold: quantities[currency].to_i,
          items_total: items[currency],
          commission: commissions[currency],
          net_received: payouts[currency]
        }
      end.values
    end
  end
end
