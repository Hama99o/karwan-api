class AddCommissionTopupToOrders < ActiveRecord::Migration[8.0]
  # WHAT WE GAVE BACK, frozen on the row at assignment.
  #
  # The top-up moves money from our commission to the courier when a job's
  # distance is worth more than its fee (Pricing::CourierTopUp). It is written
  # here rather than deducted from `commission`, and that is the whole design:
  #
  #   - `merchant_payout` is derived from `commission`, so reducing commission
  #     would silently pay the RESTAURANT more — our margin becoming their
  #     windfall, on exactly the thin orders the top-up exists to rescue, with
  #     every total still summing.
  #   - The ledger then shows the full commission owed and the top-up given
  #     back as separate movements, which is one-way door 4: a balance can be
  #     recomputed from entries, entries can never be reconstructed from a
  #     balance. "What did the top-up cost us in November" is one sum.
  #
  # DEFAULT 0 AND NOT NULL, so every order already placed reads as "nothing
  # given back", which is exactly what was true of it.
  def change
    add_column :orders, :commission_topup, :decimal, precision: 12, scale: 2,
                                                     default: "0.0", null: false
  end
end
