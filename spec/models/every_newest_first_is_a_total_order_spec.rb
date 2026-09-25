require "rails_helper"

# ═══ ORDERING BY A COLUMN THAT REPEATS IS NOT ORDERING ═════════════════════
#
# `ORDER BY period_start DESC` over rows that share a `period_start` leaves
# Postgres free to return them in **any order, and a different one per query**.
# Nothing promises otherwise — not the plan, not the insertion order, not the
# fact that it looked stable yesterday.
#
# Every one of these scopes feeds a PAGINATED list. Over tied rows that is not
# a cosmetic wobble: page 2 is `OFFSET 50` into an order that may have changed
# since page 1, so a row can appear twice and another can never appear at all.
# `MerchantStatement` is the sharp case and this is checked rather than assumed:
# `Merchants::IssueWeeklyStatementsJob` computes **one** `period_start` and
# issues a statement for every merchant with it, and `period_start` is a `date`
# — day precision, no microseconds to separate them. The unique index is
# `(merchant_id, period_start, period_end, currency)`, so **one merchant can
# hold several statements for the same period**, one per currency. Ties are the
# norm there rather than a coincidence, on both the console list and the
# merchant's own — and the list is money. A merchant shown one statement twice
# and another not at all cannot reconcile what they are owed.
#
# ── HOW THIS WAS FOUND, WHICH IS THE ARGUMENT FOR CAPTURED PAYLOADS ───────
#
# `ended_reason_payload_contract_spec.rb` went red on a full run: two orders
# swapped places. Under `travel_to` every row shares `created_at` to the
# microsecond, so `newest_first` was a tie for all seven and the captured
# fixture had pinned one arbitrary answer. The fixture was wrong to pin it AND
# the scope was wrong to permit it — and no other spec in 2,600 could have
# noticed, because none of them asserted on an order they had not chosen.
#
# ── WHY A SQL ASSERTION AND NOT A PAGING ONE ──────────────────────────────
#
# A "page through and look for duplicates" example would be the better test if
# it could fail. It cannot be relied on to: on a small table Postgres will
# usually return the same sequential scan twice, so the example would pass with
# the tiebreaker REMOVED — a green result measuring nothing, which
# `docs/TESTING.md` is mostly about. Asserting on the generated SQL is a weaker
# claim honestly made, and it goes red the moment a tiebreaker is dropped.
RSpec.describe "every newest_first is a total order" do
  # Named here rather than discovered, so adding a scope without a tiebreaker
  # fails at the list too — a reflective sweep would simply not see it. The
  # constant is uniquely named on purpose: see `no_two_specs_share_a_constant_spec.rb`.
  # MerchantStatement first: it is the one where ties are guaranteed rather
  # than unlikely, and the one whose list is money.
  NEWEST_FIRST_MODELS = [ MerchantStatement, Settlement, CourierShift, Order, Trip,
                          WalletEntry, OtpVerification, AuditLog, ErrorReport ].freeze

  it "covers every model that declares one" do
    # Eager load first: without it `descendants` is whatever this run happened
    # to autoload, which is the sweep quietly measuring nothing again.
    Rails.application.eager_load!
    declaring = ApplicationRecord.descendants.select { |model| model.respond_to?(:newest_first) }

    expect(declaring - NEWEST_FIRST_MODELS).to be_empty,
                                 "a model declares newest_first and this spec does not check it"
  end

  # ── THE TIEBREAKER MUST BE ONE THAT CANNOT ITSELF TIE ────────────────────
  #
  # Adding a second column only helps if it is unique. `id` is the primary key
  # — asserted here rather than assumed, because a tiebreaker that can tie is a
  # fix that looks like one.
  it "breaks ties on a column that cannot tie" do
    NEWEST_FIRST_MODELS.each do |model|
      expect(model.primary_key).to eq("id"), "#{model.name} does not key on id, so id is not a tiebreaker"
    end
  end

  # The guarantee that makes `period_start` tie, stated as a test so the day
  # somebody makes it unique this spec stops claiming something false.
  it "MerchantStatement really can hold several rows with one period_start" do
    week = Date.new(2026, 9, 14)
    # Built directly: there is no factory, and the unique index is
    # (merchant_id, period_start, period_end, currency), so two shops is what
    # makes two rows legal for one week — which is the point being made.
    2.times do
      MerchantStatement.create!(merchant: create(:merchant), period_start: week,
                                period_end: week + 6, currency: "AFN", issued_at: Time.current)
    end

    expect(MerchantStatement.where(period_start: week).count).to eq(2),
                                                                "period_start is unique after all, and this spec argues from a premise that is gone"
  end

  NEWEST_FIRST_MODELS.each do |model|
    it "#{model.name} breaks ties on a unique column" do
      sql = model.newest_first.to_sql

      expect(sql).to match(/ORDER BY/i)
      expect(sql).to match(/"#{model.table_name}"\."id" DESC\s*\z/i),
                     "#{model.name}.newest_first orders by a column that can repeat, and the list it " \
                     "feeds is paginated: two pages over tied rows can show one row twice and miss another"
    end
  end
end
