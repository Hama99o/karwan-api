class AddShortageMultiplierToOrders < ActiveRecord::Migration[8.0]
  # WHY THE MULTIPLIER IS ON THE ROW AND NOT ONLY IN THE SETTINGS TABLE.
  #
  # Correction 13's frozen-amount rule: every amount is written onto the order
  # at the moment it is quoted, never recomputed for display. A shortage
  # multiplier is the thing most likely to have changed by the time anybody
  # asks about it — that is its whole purpose, it goes up in a storm and comes
  # back down the same evening. "Why was my delivery 260 instead of 100 last
  # Tuesday" is a question about a number that no longer exists anywhere unless
  # this column holds it.
  #
  # TWO COLUMNS, NOT ONE, and the second is the audit:
  #
  #   shortage_multiplier           what was actually applied
  #   shortage_multiplier_requested what the console said at the time
  #
  # They differ only when `max_total_multiplier` bit, so a capped fare is
  # distinguishable from an uncapped one without a boolean that could disagree
  # with the numbers beside it. It also records an operator's mistyped 10 —
  # which is the event most worth being able to find later, and the reason the
  # cap exists at all.
  #
  # DEFAULT 1.0 AND NOT NULL, so every order already placed reads as "no
  # shortage applied", which is exactly what was true of it.
  def change
    add_column :orders, :shortage_multiplier, :decimal, precision: 5, scale: 3,
                                                        default: "1.0", null: false
    add_column :orders, :shortage_multiplier_requested, :decimal, precision: 5, scale: 3,
                                                                  default: "1.0", null: false
  end
end
