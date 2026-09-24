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

    def self.for(courier, since: DEFAULT_WINDOW.ago) = new(courier, since: since).call

    def initialize(courier, since: DEFAULT_WINDOW.ago)
      @courier = courier
      @since = since
    end

    def call
      answers = Offer.where(courier: @courier, offered_at: @since..)
                     .where(status: ANSWERED).group(:status).count
      offers = answers.values.sum

      ended = rides_ended_mid_way
      {
        offers: offers,
        accepted: answers["accepted"].to_i,
        declined: answers["declined"].to_i,
        timed_out: answers["timed_out"].to_i,
        rides_ended_mid_way: ended.count,
        repeated_passengers: repeated_passengers(ended),
        since: @since
      }
    end

    private

    def rides_ended_mid_way
      Trip.where(courier: @courier, status: :failed, failed_at: @since..).where.not(in_progress_at: nil)
    end

    # passenger_id => how many of this driver's rides with them ended mid-way,
    # for passengers where that happened more than once.
    def repeated_passengers(ended)
      ended.group(:passenger_id).having("COUNT(*) > 1").count
    end
  end
end
