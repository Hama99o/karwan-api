module Merchants
  # ── WHAT THIS SHOP DID TO THE ORDERS IT WAS SENT ──────────────────────────
  #
  # `TRUST_AND_REPUTATION.md` §5-B states its own gap and calls the case
  # **THE DAMAGING ONE**: *"What is missing is that cancellation reasons should
  # be tracked per restaurant, so a restaurant cancelling a fifth of its orders
  # is visible before its customers leave."* And §5-C: *"No penalty does not
  # mean no visibility... Visibility is not a penalty, and the data is already
  # recorded."*
  #
  # It was recorded and nothing read it per shop. `Admin::ReportsController`
  # counts reasons ACROSS the platform, which answers "why do orders fail" and
  # cannot answer "which shop do I ring" — and the second is the one Hamma9900
  # acts on, because he knows all ten personally.
  #
  # ── FOUR OUTCOMES, KEPT APART, BECAUSE THEY ARE FOUR CONVERSATIONS ────────
  #
  #   refused                   the shop decided: out of stock, too busy, closing
  #   never_answered            nobody touched the tablet and the timeout closed it
  #   cancelled_after_accepting taken, then dropped — §5-B's own case
  #   delivered / still running not counted, but IN THE DENOMINATOR
  #
  # Merging the first two is the mistake the platform report already records
  # making: *"three shops never looked at the tablet and one shop made a
  # decision. Added together the page says four shops keep closing early, and
  # the owner rings four restaurants about a problem three of them do not
  # have."* A shop that answers and says no is a supply problem; a shop that
  # never answers is a broken tablet. Different phone calls.
  #
  # ── TWO READINGS, ONE SET OF DEFINITIONS ──────────────────────────────────
  #
  # `.for(merchant)` answers for one shop, on its console page. `.ranked`
  # answers for all of them, on the report — which is the one §5-B actually
  # asks for, because a number on one shop's page is only visible to somebody
  # who already suspects that shop.
  #
  # **Both read the scopes below and neither restates them.** Writing the
  # ranking as its own queries is how the report and the shop's page come to
  # disagree about the same restaurant, and two answers to one question is the
  # defect this repo keeps finding.
  #
  # ── WHO DID IT COMES FROM THE TRANSITION LOG ──────────────────────────────
  #
  # Not from `orders.cancelled_by_role`, which is written by two paths, never by
  # the timeout job, and read by nothing — see `docs/NOTES.md`. The log is the
  # one-way door, and `Orders::EndedReason` reads it the same way.
  #
  # DERIVED, NEVER STORED, for the reason `User#delivery_failures` is: the
  # orders already carry the outcomes, and a cached tally is a second answer
  # that can disagree with them.
  class Reliability
    # The shop's own reasons. `no_answer` is the system's and is deliberately
    # absent — this is `Order::MERCHANT_REJECTION_REASONS`, the same list the
    # board offers, so the reject sheet and this count cannot drift apart.
    DECIDED_REASONS = Order::MERCHANT_REJECTION_REASONS

    # *"A fifth of its orders"* is a rate over a period. Thirty days is what
    # `User#recent_delivery_failures` already uses for the same kind of question.
    DEFAULT_WINDOW = 30.days

    # A shop with three orders and one refusal is at 33% and means nothing. The
    # ranking exists so Hamma9900 knows which of ten restaurants to ring, and
    # sending him to one that had a single bad evening is worse than sending him
    # nowhere — he spends a relationship and finds nothing.
    #
    # Five is deliberately low, because ten restaurants in one neighbourhood do
    # not produce large numbers quickly. It is a floor on NOISE rather than a
    # significance test, and every row carries its own denominator so the reader
    # can judge it.
    MIN_ORDERS_TO_RANK = 5

    # ══ THE DEFINITIONS. Everything else in this file reads these. ══════════

    # The shop answered and said no, with a reason from its own sheet.
    #
    # `by_merchant_owner` rather than "has an actor at all": `Order::TRANSITIONS`
    # lets an **admin** reject too (`placed: { rejected: [merchant_owner,
    # admin] }`) and there is no console route for it today. A looser test would
    # be identical now and would quietly start filing an operator's decision as
    # the shop's the day that route is added — an operator rejecting on the
    # phone writes a MERCHANT reason with an operator as the actor.
    def self.refusals_in(scope)
      rejected = scope.where(status: :rejected)
      rejected.where(id: transitions_into(rejected).by_merchant_owner.select(:subject_id))
              .where(rejection_reason: DECIDED_REASONS)
    end

    # NOBODY acted — neither an app user nor an operator in the console. That is
    # `StatusTransition#system?` in SQL, and both columns are checked for the
    # reason that method checks both: a console operator has no `actor_id` and
    # is not the system.
    def self.unanswered_in(scope)
      rejected = scope.where(status: :rejected)
      rejected.where(id: transitions_into(rejected)
                          .where(actor_id: nil, admin_user_id: nil).select(:subject_id))
    end

    # ── §5-B ITSELF: taken, then dropped ────────────────────────────────────
    #
    # `accepted_at` present is what separates this from a refusal at the door:
    # the customer had been told yes.
    #
    # AND THERE IS NO `by_customer` FILTER, DELIBERATELY. The obvious version
    # excludes the customer's own cancellations — theirs are the commonest kind
    # and counting them would make every busy shop look unreliable. **That
    # filter could never fire.** `Order::TRANSITIONS` gives `cancelled` to a
    # customer from **`placed` only**; after that it is `merchant_owner` or
    # `admin`. So an order with `accepted_at` set is not one they could have
    # cancelled, and a condition that cannot remove a row is a check that cannot
    # fail. The assumption is PINNED in the spec instead, and that spec names
    # this method when it breaks.
    #
    # An ADMIN cancellation IS counted, and that is the point: the merchant app
    # has no cancel route (`PRODUCT.md` gives the restaurant accept, reject and
    # ready), so a shop that runs out mid-cook rings the office and an operator
    # does it. Excluding those makes the one case §5-C describes invisible.
    def self.dropped_after_accepting_in(scope)
      scope.where(status: :cancelled).where.not(accepted_at: nil)
    end

    # ── WHY NOBODY ANSWERED, WHICH IS THREE DIFFERENT PHONE CALLS AGAIN ─────
    #
    # `docs/NOTES.md` measured the trap this closes, and measured it BEFORE this
    # column existed: at 21:08 on the rig, **23 of 32** shops that were toggled
    # open and had posted hours were outside those hours. *"Not an edge case —
    # it is what a shop looks like most evenings, because the toggle is what
    # people forget."*
    #
    # A shop that forgot its toggle is orderable into an empty kitchen. The
    # order sits in `placed`, the timeout closes it as `no_answer`, and it lands
    # in `never_answered` — so that column, left whole, would be **dominated by
    # forgotten toggles** and read as "shops are not watching their tablets".
    # That is the same mistake this whole service exists to avoid, one level
    # down: the owner rings about a tablet when the problem is a switch.
    #
    #   outside_posted_hours  the shop's own week says it was shut — a toggle
    #   during_posted_hours   it said it was open and nobody answered — a tablet
    #   no_hours_posted       it has never posted a week, so nothing can be said
    #
    # The third is not folded into the second, for the reason the platform
    # report keeps `unrecorded` separate: *"an order whose rejection was never
    # recorded is counted as itself rather than attributed to a cause."* It is
    # also its own small action — ask the shop for its hours.
    #
    # NOTHING HERE DECIDES THE POLICY. `docs/NOTES.md` reserves that for
    # Hamma9900 with three costed options; no order is blocked and no toggle is
    # touched. This only stops the number lying about which of them it is.
    #
    # TWO QUERIES, whatever the number of orders or shops: the unanswered rows,
    # then every posted week they belong to.
    #
    # `scope` must already be filtered to a `placed_at` window — both callers
    # are — which is also what guarantees a time to compare against the week.
    # The spec asserts the causes SUM to the count they explain, so a row
    # skipped for any reason is loud rather than quietly missing.
    def self.unanswered_causes(scope)
      rows = unanswered_in(scope).pluck(:merchant_id, :placed_at)
      return Hash.new { |h, k| h[k] = Hash.new(0) } if rows.empty?

      weeks = MerchantOpeningHour.where(merchant_id: rows.map(&:first).uniq).group_by(&:merchant_id)

      rows.each_with_object(Hash.new { |h, k| h[k] = Hash.new(0) }) do |(merchant_id, placed_at), tally|
        posted = weeks[merchant_id]
        cause = if posted.blank?
                  :no_hours_posted
        elsif Merchant.open_per_schedule?(placed_at, posted)
                  :during_posted_hours
        else
                  :outside_posted_hours
        end
        tally[merchant_id][cause] += 1
      end
    end

    # A RELATION, not a list of ids — plucking would pull every order's id into
    # Ruby to hand straight back to Postgres.
    def self.transitions_into(scope, status = :rejected)
      StatusTransition.where(subject_type: Order.name, to_status: status.to_s,
                             subject_id: scope.select(:id))
    end

    # ══ READING ONE SHOP ═══════════════════════════════════════════════════

    def self.for(merchant, since: DEFAULT_WINDOW.ago) = new(merchant, since: since).call

    # ══ READING EVERY SHOP, FOR THE PAGE THAT ANSWERS "WHO DO I RING" ══════
    #
    # FOUR GROUPED QUERIES, not one per merchant. Calling `.for` in a loop over
    # 45 shops is the shape `docs/NOTES.md` records costing the public catalog
    # 102 queries, and a report is exactly where that goes unnoticed.
    def self.ranked(since: DEFAULT_WINDOW.ago, limit: 10)
      scope = Order.where(placed_at: since..)
      totals = scope.group(:merchant_id).count
      return [] if totals.empty?

      refused = refusals_in(scope).group(:merchant_id).count
      unanswered = unanswered_in(scope).group(:merchant_id).count
      dropped = dropped_after_accepting_in(scope).group(:merchant_id).count
      causes = unanswered_causes(scope)

      rows = totals.filter_map do |merchant_id, orders|
        next if orders < MIN_ORDERS_TO_RANK

        lost = refused[merchant_id].to_i + unanswered[merchant_id].to_i + dropped[merchant_id].to_i
        next if lost.zero?

        { merchant_id: merchant_id, orders: orders,
          refused: refused[merchant_id].to_i,
          never_answered: unanswered[merchant_id].to_i,
          unanswered_causes: causes[merchant_id],
          cancelled_after_accepting: dropped[merchant_id].to_i,
          unfulfilled: lost, unfulfilled_rate: (lost.to_f / orders * 100).round(1) }
      end

      rows.sort_by { |row| -row[:unfulfilled_rate] }.first(limit)
    end

    def initialize(merchant, since: DEFAULT_WINDOW.ago)
      @merchant = merchant
      @since = since
    end

    def call
      {
        orders: orders.count,
        refused: refused_by_reason,
        never_answered: self.class.unanswered_in(orders).count,
        unanswered_causes: self.class.unanswered_causes(orders)[@merchant.id],
        cancelled_after_accepting: self.class.dropped_after_accepting_in(orders).count,
        unfulfilled: unfulfilled_count,
        unfulfilled_rate: unfulfilled_rate,
        since: @since
      }
    end

    private

    # EVERY order the shop was sent in the window, including the ones that went
    # well. The denominator is the whole point: ten refusals out of a thousand
    # orders is a good restaurant having a bad week, and ten out of forty is a
    # conversation.
    #
    # `placed_at` rather than `created_at`: it is the moment the shop was asked,
    # and it is the column the rest of the reporting groups on.
    def orders
      @orders ||= @merchant.orders.where(placed_at: @since..)
    end

    def refused_by_reason
      self.class.refusals_in(orders).group(:rejection_reason).count.sort_by { |_reason, n| -n }
    end

    def unfulfilled_count
      refused_by_reason.sum { |_reason, n| n } +
        self.class.unanswered_in(orders).count +
        self.class.dropped_after_accepting_in(orders).count
    end

    # Nil rather than zero when the shop had no orders at all. A new restaurant
    # with nothing to show is not a restaurant with a perfect record, and 0%
    # beside a shop nobody has ordered from is a claim the data cannot make.
    def unfulfilled_rate
      total = orders.count
      return nil if total.zero?

      (unfulfilled_count.to_f / total * 100).round(1)
    end
  end
end
