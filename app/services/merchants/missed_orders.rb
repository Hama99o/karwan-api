module Merchants
  # ORDERS THE KITCHEN NEVER ANSWERED, TODAY (Kabul's day).
  #
  # A placed order the shop doesn't answer closes itself as `no_answer`
  # (Dispatch::JobTimeoutsJob). The alarm and the board poll are
  # foreground-only, so a kitchen away from its tablet had no way to learn,
  # afterwards, that it lost one: nothing counted them (karwan-42 via
  # Hamma9901, 25 Sept 2026). This does, from the orders themselves:
  #   `count`  for /merchant/today ("missed today: 2");
  #   `last`   for the board poll, the most recent one today, so a notice
  #            survives the app having been backgrounded rather than
  #            depending on the poll having watched the order appear and
  #            vanish. The app de-duplicates by `code`.
  class MissedOrders
    def initialize(merchant, now: Time.current)
      @merchant = merchant
      @now = now
    end

    def count = scope.count

    # Just the code, for the board's ETag: one scalar before the 304 check,
    # never a loaded row (the_board_answers_not_modified_spec guards that).
    def last_code = newest.pick(:code)

    def last
      order = newest.first
      order && { code: order.code, placed_at: order.placed_at, missed_at: order.rejected_at }
    end

    private

    def newest = scope.order(rejected_at: :desc, id: :desc)

    def scope
      @merchant.orders.where(status: :rejected, rejection_reason: :no_answer, rejected_at: @now.in_time_zone.all_day)
    end
  end
end
