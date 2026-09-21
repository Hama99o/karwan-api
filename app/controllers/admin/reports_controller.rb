# The numbers PRODUCT.md asks for and the landing page deliberately does not
# carry: *"orders per day, revenue, commission earned, rider utilisation (orders
# per rider per day — the number that decides the business), failure reasons
# ranked."*
#
# The dashboard answers "what needs attention right now". This answers "is the
# business working", which is a different question asked at a different moment,
# and mixing them makes the urgent tiles harder to read.
#
# ── THREE RULES TAKEN FROM THE REST OF THIS REPO ──────────────────────────
#
# 1. **Grouped by currency, never summed across it.** Same as the dashboard's
#    `commission_since`. `Monetary::SUPPORTED_CURRENCIES` has one entry today
#    and the schema treats currency as a real dimension, so a report that adds
#    AFN to anything else is a bug waiting for the second currency.
#
# 2. **Revenue and commission are NOT the same number and are never shown as
#    one.** Under Model A the customer pays the courier, the courier pays the
#    merchant, and *our* income is the commission. Gross order value is what
#    passed through; commission is what we earned. An owner shown one labelled
#    as the other would think this business is 20× its size.
#
# 3. **Show the numerator and the denominator, not only the ratio.** The
#    settlement screen shows expected AND counted for the same reason: a
#    courier told only the variance cannot check it. "1.8 orders per rider"
#    is unauditable; "54 deliveries ÷ 6 riders ÷ 5 days" can be argued with.
module Admin
  class ReportsController < Admin::ApplicationController
    DAYS = 14

    def index
      @days = DAYS
      @from = DAYS.days.ago.beginning_of_day

      @per_day = orders_per_day
      @gross_value = gross_value_since(@from)
      @commission = commission_since(@from)
      @utilisation = utilisation_since(@from)
      @failures = failure_reasons_ranked
    end

    private

    # ── THE DAY IS KABUL'S, NOT THE SERVER'S ────────────────────────────────
    #
    # Written first as `DATE(created_at)`, which is the UTC date, and MEASURED
    # to be wrong: an order at 21:00Z is 01:30 the NEXT day in Kabul, so plain
    # `DATE()` reports 2026-09-20 where Kabul says 2026-09-21. Kabul is UTC+4:30,
    # so everything between 19:30 and midnight local — **the dinner rush, the
    # busiest hours of a food delivery business** — would have been attributed
    # to the previous day, and "our best evening" would be split across two rows.
    #
    # `config.time_zone` is Kabul and `docs/NOTES.md` already records one bug
    # from this exact confusion in opening hours. Grouping goes through
    # `AT TIME ZONE` so the row boundary is the one the shopkeeper lives in.
    # TWO CONVERSIONS, NOT ONE. These columns are `timestamp WITHOUT time zone`
    # holding UTC, which is Rails' convention. On such a column a single
    # `AT TIME ZONE 'Asia/Kabul'` means "READ this naive value AS Kabul time" —
    # the opposite of the intent, and it shifts the wrong way.
    #
    # `AT TIME ZONE 'UTC'` first says what the stored value means; the second
    # converts it to Kabul. Measured: an order at 21:00Z landed on 19 Sep under
    # the single-conversion version — the same answer as no conversion at all,
    # which is how a broken fix passes for a working one.
    KABUL_DATE = "DATE(%s AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Kabul')".freeze

    # Placed and delivered side by side. Placed alone hides a day where
    # everything was ordered and nothing arrived, which is the day worth seeing.
    def orders_per_day
      placed = Order.where(created_at: @from..).group(Arel.sql(format(KABUL_DATE, "created_at"))).count
      delivered = Order.where(status: :delivered, delivered_at: @from..)
                       .group(Arel.sql(format(KABUL_DATE, "delivered_at"))).count
      rides = Trip.where(status: :completed, completed_at: @from..)
                  .group(Arel.sql(format(KABUL_DATE, "completed_at"))).count

      (@from.to_date..Time.zone.today).map do |date|
        { date: date, placed: placed[date].to_i, delivered: delivered[date].to_i, rides: rides[date].to_i }
      end.reverse
    end

    # WHAT CUSTOMERS PAID — not ours. Named `gross_value` rather than `revenue`
    # so nobody reads it as income at a glance.
    def gross_value_since(from)
      orders = Order.where(status: :delivered, delivered_at: from..).group(:currency).sum(:customer_total)
      trips = Trip.where(status: :completed, completed_at: from..).group(:currency).sum(:fare)

      orders.merge(trips) { |_currency, a, b| a + b }
    end

    # OURS. Same query the dashboard uses, so the two pages cannot disagree.
    def commission_since(from)
      orders = Order.where(status: :delivered, delivered_at: from..).group(:currency).sum(:commission)
      trips = Trip.where(status: :completed, completed_at: from..).group(:currency).sum(:commission)

      orders.merge(trips) { |_currency, a, b| a + b }
    end

    # ── THE NUMBER THAT DECIDES THE BUSINESS ────────────────────────────────
    #
    # PRODUCT.md calls it that, which makes every term in it a decision rather
    # than a query. All four are made here and repeated on the page, because a
    # hiring decision will be made on this figure:
    #
    #   NUMERATOR   delivered orders + completed rides. Cancelled and failed
    #               jobs are NOT counted: a rider who took an order that failed
    #               did work, but the business did not get a delivery, and this
    #               figure answers "what did we get".
    #   DENOMINATOR riders who completed AT LEAST ONE job in the period.
    #   DAYS        calendar days in the window, Kabul's.
    #   WINDOW      the same 14 days as everything else on the page.
    #
    # ── AND THE BIAS IN THE DENOMINATOR, WHICH RUNS THE WRONG WAY ───────────
    #
    # A rider who was online all day and took nothing is NOT in the denominator,
    # so idle capacity is invisible and **this figure flatters the business**.
    # If it says 1.8 jobs per rider per day, the true figure against everyone who
    # made themselves available is lower, possibly much lower.
    #
    # It cannot be computed today: `courier_profiles.is_available` is a CURRENT
    # state with no history, and there is no shifts table. Measuring idle
    # capacity needs somewhere to record when a rider went on and off shift.
    # That is a schema decision with a cost, so it is written up in
    # `docs/NOTES.md` rather than decided here — and the bias is stated on the
    # page so nobody hires against a number that only counts the busy.
    def utilisation_since(from)
      deliveries = Order.where(status: :delivered, delivered_at: from..)
      rides = Trip.where(status: :completed, completed_at: from..)

      jobs = deliveries.count + rides.count
      couriers = (deliveries.distinct.pluck(:courier_id) + rides.distinct.pluck(:courier_id)).compact.uniq.size
      days = [ (Time.zone.today - from.to_date).to_i, 1 ].max

      # ── THE HONEST DENOMINATOR, ONCE THERE IS HISTORY TO USE ──────────────
      #
      # Couriers who were AVAILABLE in the window, from `courier_shifts` —
      # including the ones who went online and took nothing, who are exactly
      # the capacity the working-courier figure hides.
      #
      # `history_from` is stated because the table began recording on the day it
      # shipped and **cannot be backfilled**. A window that predates it would
      # otherwise divide by a denominator that is missing most of its subjects
      # and report a crisis, which is the same error in the opposite direction.
      available = CourierShift.overlapping(from, Time.current).distinct.count(:courier_id)
      history_from = CourierShift.minimum(:started_at)

      {
        jobs: jobs, couriers: couriers, days: days,
        per_courier_per_day: couriers.zero? ? nil : (jobs.to_f / couriers / days).round(2),
        available_couriers: available,
        history_from: history_from,
        history_covers_window: history_from.present? && history_from <= from,
        per_available_per_day: available.zero? ? nil : (jobs.to_f / available / days).round(2)
      }
    end

    # Both demand types, ranked, over THE SAME WINDOW as everything else on the
    # page. Written first with no date filter, which would have put an all-time
    # ranking beside fourteen-day figures under one heading — two periods on one
    # screen, with nothing saying so.
    #
    # A reason that never occurs is omitted rather than shown as zero: a column
    # of zeroes teaches nobody anything and hides the one that is climbing. A
    # reason the server has stopped emitting therefore disappears from this list
    # once it leaves the window, which is the intended behaviour — this is a
    # report on the last fourteen days, not a catalogue of the enum.
    def failure_reasons_ranked
      orders = Order.where(status: :failed, updated_at: @from..)
                    .where.not(failure_reason: nil).group(:failure_reason).count
      trips = Trip.where(status: :failed, updated_at: @from..)
                  .where.not(failure_reason: nil).group(:failure_reason).count

      merged = orders.merge(trips) { |_reason, a, b| a + b }
      merged.sort_by { |_reason, count| -count }
    end
  end
end
