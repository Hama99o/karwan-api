module Couriers
  # ── WHAT THIS COURIER DID WITH THE WORK HE WAS SENT ───────────────────────
  #
  # `Merchants::Reliability` answers "which shop do I ring". This is the same
  # question about the other side of the counter, and `TRUST_AND_REPUTATION.md`
  # §5 asks it twice:
  #
  # **§5-A.** *"A rider accepts quickly so nobody else takes it, then sees the
  # distance and cancels. That is normal behaviour... **But it needs a limit** —
  # a rider who cancels half his offers is gaming the queue, and that is a
  # reason code, not a strike."*
  #
  # **§5-E**, a ride ended after it started: *"Detection — an unusually high
  # cancellation rate for one driver, or the same driver-passenger pair
  # cancelling repeatedly, both visible in data already collected."*
  #
  # Both were collected — `offers` keeps every answer, the trip keeps
  # `in_progress_at` — and nothing read either per courier.
  #
  # ── WHAT §5-A LOOKS LIKE IN THIS CODE ─────────────────────────────────────
  #
  # There is no route for a courier to cancel a job after accepting it. So
  # "accepts then cancels" cannot happen here; what CAN is the two ways of
  # saying no — tapping decline, or letting the offer run out. They are kept
  # apart for the reason `Merchants::Reliability` keeps refused and
  # never-answered apart: a courier who declines has looked and chosen; one
  # whose offers time out is not looking, and every timeout is a minute a
  # customer waited for the next courier to be asked. Different conversations.
  #
  # `superseded` offers are left out of the denominator as well as the count:
  # somebody else took the job before this courier answered, which is nothing
  # he did.
  #
  # ── WHAT §5-E LOOKS LIKE ──────────────────────────────────────────────────
  #
  # A trip that reached `in_progress` and then `failed` — the passenger was in
  # the car and the ride did not finish. `Trip::TRANSITIONS` allows no other
  # exit from `in_progress`. The PAIRS are passengers who appear in two or more
  # of this driver's rides ended that way, which is §5-E's fraud shape: *"they
  # tell the customer to cancel, to keep the commission."*
  #
  # ── NO LIMIT HERE, DELIBERATELY ───────────────────────────────────────────
  #
  # §5-A says it *"needs a limit"* and does not say what the limit is or what
  # happens at it; §5 is the open design conversation. So this counts, with the
  # denominator on every figure, and decides nothing — the same line
  # `User#delivery_failures` and `Merchants::Reliability` hold.
  #
  # DERIVED, NEVER STORED: the offers and trips already carry the outcomes.
  class Reliability
    DEFAULT_WINDOW = Merchants::Reliability::DEFAULT_WINDOW

    # The courier's own answers. `offered` is still open and is not an answer.
    ANSWERED = %w[accepted declined timed_out].freeze

    # Same floor as the shop ranking and for its reason: four offers and two
    # declines is 50% and means nothing. A floor on noise, not a test; every
    # row carries its denominator.
    MIN_OFFERS_TO_RANK = Merchants::Reliability::MIN_ORDERS_TO_RANK

    # ══ THE DEFINITIONS. `.for` and `.ranked` both read these. ═════════════
    #
    # Two readings of one question must not come to disagree about the same
    # courier, which is why `Merchants::Reliability` is built this way too.

    def self.answered_offers(since)
      Offer.where(offered_at: since.., status: ANSWERED)
    end

    def self.rides_ended_mid_way(since)
      Trip.where(status: :failed, failed_at: since..).where.not(in_progress_at: nil)
    end

    # ══ READING ONE COURIER ═════════════════════════════════════════════════

    def self.for(courier, since: DEFAULT_WINDOW.ago) = new(courier, since: since).call

    # ══ READING EVERY COURIER, FOR THE REPORT ═══════════════════════════════
    #
    # §5-E says *"unusually high"*, which only means something against the
    # others — and a figure on one courier's page is only seen by somebody who
    # already suspects him. THREE GROUPED QUERIES, whatever the fleet size.
    #
    # Listed: a courier with enough answered offers who did not take some of
    # them, ranked by the share not taken; and ANY courier with a recurring
    # mid-ride passenger, whatever his volume, because that is §5-E's fraud
    # shape rather than a rate. Those come first.
    def self.ranked(since: DEFAULT_WINDOW.ago, limit: 10)
      answers = answered_offers(since).group(:courier_id, :status).count
      ended = rides_ended_mid_way(since).group(:courier_id).count
      pairs = rides_ended_mid_way(since).group(:courier_id, :passenger_id).having("COUNT(*) > 1").count

      by_courier = Hash.new { |h, k| h[k] = Hash.new(0) }
      answers.each { |(courier_id, status), n| by_courier[courier_id][status] = n }
      repeated = pairs.each_with_object(Hash.new { |h, k| h[k] = {} }) do |((courier_id, passenger_id), n), acc|
        acc[courier_id][passenger_id] = n
      end

      rows = (by_courier.keys | repeated.keys).filter_map do |courier_id|
        tally = by_courier[courier_id]
        offers = tally.values.sum
        not_taken = tally["declined"] + tally["timed_out"]
        flagged_rate = offers >= MIN_OFFERS_TO_RANK && not_taken.positive?
        next unless flagged_rate || repeated.key?(courier_id)

        { courier_id: courier_id, offers: offers, accepted: tally["accepted"],
          declined: tally["declined"], timed_out: tally["timed_out"],
          not_taken_rate: offers.zero? ? nil : (not_taken.to_f / offers * 100).round(1),
          rides_ended_mid_way: ended[courier_id].to_i,
          repeated_passengers: repeated.fetch(courier_id, {}) }
      end

      rows.sort_by { |row| [ row[:repeated_passengers].empty? ? 1 : 0, -row[:not_taken_rate].to_f ] }.first(limit)
    end

    def initialize(courier, since: DEFAULT_WINDOW.ago)
      @courier = courier
      @since = since
    end

    def call
      answers = self.class.answered_offers(@since).where(courier: @courier).group(:status).count
      ended = self.class.rides_ended_mid_way(@since).where(courier: @courier)

      {
        offers: answers.values.sum,
        accepted: answers["accepted"].to_i,
        declined: answers["declined"].to_i,
        timed_out: answers["timed_out"].to_i,
        rides_ended_mid_way: ended.count,
        repeated_passengers: ended.group(:passenger_id).having("COUNT(*) > 1").count,
        since: @since
      }
    end
  end
end
