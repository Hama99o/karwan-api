module Merchants
  # Issues last week's statement for every live shop.
  #
  # ── THE WEEK IS THE SAME WEEK FOR EVERY SHOP ──────────────────────────────
  #
  # Cut on a schedule rather than on request, so two merchants comparing notes
  # are comparing the same seven days. A merchant-triggered issue would let one
  # shop's "week" end on Tuesday and another's on Thursday, and the first
  # question anybody asks about a statement is whether it matches somebody
  # else's.
  #
  # ── KABUL'S WEEK ──────────────────────────────────────────────────────────
  #
  # `Time.zone` is Kabul, so `Date.current` is Kabul's date and the boundary is
  # the one the shopkeeper lives in. This matters here for the same reason it
  # mattered in the reports page: an order delivered at 21:00Z is the next day
  # in Kabul, and a week cut on the server's date would put the busiest hours of
  # the last evening into the following statement.
  #
  # Idempotent: `IssueStatement` finds or creates, and the unique index makes
  # that true under a retry as well as under a re-run.
  class IssueWeeklyStatementsJob < ApplicationJob
    queue_as :default

    # ── A FIXED WEEK, NOT A ROLLING SEVEN DAYS ────────────────────────────
    #
    # Written first as `Date.current.yesterday` minus six, which slides: run
    # daily, it would issue a DIFFERENT seven-day window every morning and hand
    # a merchant a new overlapping statement each day. "Weekly" would have been
    # the name of the job and not a property of the output.
    #
    # The boundary is the AFGHAN week — Saturday to Friday — so the period ends
    # on the most recent Friday that has fully passed. A daily schedule then
    # re-issues the same completed week, which `IssueStatement` makes a no-op,
    # so a missed morning is caught by the next one at no cost.
    def perform(period_end: Date.current.prev_occurring(:friday), days: 7)
      period_start = period_end - (days - 1)
      issued = 0

      Merchant.kept.status_active.find_each do |merchant|
        issued += IssueStatement.new(merchant, period_start: period_start, period_end: period_end).call.size
      end

      Rails.logger.info("[statements] issued #{issued} for #{period_start}..#{period_end}")
      issued
    end
  end
end
