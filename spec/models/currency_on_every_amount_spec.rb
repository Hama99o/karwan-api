require "rails_helper"

# ── ONE-WAY DOOR 2 ─────────────────────────────────────────────────────────
#
# `CLAUDE.md`: *"Currency on every amount. One column, from the first migration.
# Without it a second currency is impossible to add safely, and totals across
# currencies are a bug that has already shipped in this owner's other app."*
#
# It holds today. Nothing enforced it, and the failure is not a wrong number —
# it is a column added without one, discovered when a second currency arrives
# and every historical row is ambiguous. That cannot be backfilled: you cannot
# ask a 2026 row what currency it was in.
#
# ── WHY THIS IS AN INVERSION RATHER THAN A SEARCH FOR MONEY COLUMNS ────────
#
# The obvious gate looks for columns named like money — `*_amount`, `*_total`,
# `*_fee` — and it does not work. Written that way first, it reported a clean
# schema while missing `wallet_entries.amount` (no underscore) and every column
# in `pricing_rates`: **`base`, `per_km`, `per_minute`, `minimum`** are all
# money and not one of them contains a money word.
#
# **Money columns are not reliably named, so a name-based gate reports a clean
# result on a schema it cannot read** — the shape this repo met four times on
# 2026-09-19. So the question is inverted: every DECIMAL column must be
# accounted for, either by sitting in a table that carries `currency`, or by
# being named here as something that is not money. A new decimal fails until
# somebody says which it is.
RSpec.describe "currency on every amount" do
  # Decimals that are NOT money, with the reason. A degree is not a price and a
  # multiplier is not an amount.
  NOT_MONEY = {
    "latitude" => "a coordinate", "longitude" => "a coordinate",
    "delivery_latitude" => "a coordinate", "delivery_longitude" => "a coordinate",
    "pickup_latitude" => "a coordinate", "pickup_longitude" => "a coordinate",
    "dropoff_latitude" => "a coordinate", "dropoff_longitude" => "a coordinate",
    "last_latitude" => "a coordinate", "last_longitude" => "a coordinate",
    "courier_latitude" => "a coordinate", "courier_longitude" => "a coordinate",
    "courier_arrived_latitude" => "a coordinate", "courier_arrived_longitude" => "a coordinate",
    "distance_km" => "a distance", "origin_snap_metres" => "a distance",
    "destination_snap_metres" => "a distance",
    "shortage_multiplier" => "a multiplier applied TO an amount, not an amount",
    "shortage_multiplier_requested" => "a multiplier",
    "commission_rate" => "a percentage — it has no currency of its own"
  }.freeze

  def decimal_columns
    conn = ActiveRecord::Base.connection
    conn.tables.reject { |t| t.start_with?("ar_internal", "schema_") }.flat_map do |table|
      cols = conn.columns(table)
      has_currency = cols.any? { |c| c.name == "currency" }
      cols.select { |c| c.type == :decimal }.map { |c| [ table, c.name, has_currency ] }
    end
  end

  it "keeps every money column in a table that carries a currency" do
    unaccounted = decimal_columns.reject { |_, name, has_currency| has_currency || NOT_MONEY.key?(name) }

    expect(unaccounted).to be_empty,
                           "these decimal columns are neither in a table with a `currency` column nor named " \
                           "as non-money: #{unaccounted.map { |t, c, _| "#{t}.#{c}" }.join(', ')}. " \
                           "If it is money, the table needs a currency column in the SAME migration — it " \
                           "cannot be backfilled, because a historical row cannot be asked what currency it " \
                           "was in. If it is not money, name it in NOT_MONEY with the reason."
  end

  # Guards the guard. If the introspection ever returned nothing — a renamed
  # type, a connection quirk — the example above would pass while checking
  # nothing at all.
  it "is actually reading the schema" do
    all = decimal_columns

    expect(all.size).to be > 30, "only #{all.size} decimal columns found; the introspection is not working"
    expect(all.map { |t, c, _| "#{t}.#{c}" }).to include("wallet_entries.amount", "pricing_rates.base"),
                                                 "the scan is missing money columns it must be able to see"
  end

  # The names in NOT_MONEY have to keep meaning something. A stale exemption is
  # how a real money column inherits a pass from a column that no longer exists.
  it "exempts nothing that has left the schema" do
    live = decimal_columns.map { |_, name, _| name }.uniq
    stale = NOT_MONEY.keys - live

    expect(stale).to be_empty,
                     "NOT_MONEY exempts columns that no longer exist: #{stale.join(', ')}. " \
                     "Remove them, or a future column reusing the name inherits the exemption silently."
  end
end
