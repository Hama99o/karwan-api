# WHAT A SHOP WAS PAID, AS IT WAS SAID AT THE TIME.
#
# R19, in Hamma9900's words: *"merchants and couriers each need their own
# earnings view... What they want is a statement: sales, commission deducted,
# net received."*
#
# ── SNAPSHOT, NOT A QUERY ─────────────────────────────────────────────────
#
# R19 states the constraint and gives the reason: a statement recomputed on
# demand is silently rewritten by any later change to the calculation, so the
# figure a merchant was shown last month becomes a figure nobody can reproduce.
# It is the same argument that makes `order_items` a snapshot and one-way door 1
# what it is — and `settlements` already works this way.
#
# ── ALL THREE AMOUNTS ARE STORED, AND NONE IS DERIVED ─────────────────────
#
# `net_received` could be `items_total - commission` and must not be: a residual
# agrees with itself by construction and can never disagree with the ledger it
# is supposed to describe. Each is summed from its own column on the orders, and
# a spec asserts they reconcile — which is an assertion only because they came
# from different places.
#
# ── ONE ROW PER CURRENCY ──────────────────────────────────────────────────
#
# One-way door 2. A merchant trading in two currencies gets two rows for the
# period rather than one meaningless total.
class CreateMerchantStatements < ActiveRecord::Migration[8.1]
  def change
    create_table :merchant_statements do |t|
      t.references :merchant, null: false, foreign_key: true
      t.date :period_start, null: false
      t.date :period_end, null: false
      t.string :currency, null: false

      t.integer :orders_count, null: false, default: 0
      t.decimal :items_total, precision: 12, scale: 2, null: false, default: 0
      t.decimal :commission, precision: 12, scale: 2, null: false, default: 0
      t.decimal :net_received, precision: 12, scale: 2, null: false, default: 0

      t.datetime :issued_at, null: false

      t.timestamps
    end

    # ISSUANCE IS IDEMPOTENT AT THE DATABASE, not only in the service. A weekly
    # job that runs twice — a retry, a redeploy, a manual re-run — must not hand
    # a merchant two statements for one week, and a uniqueness check in Ruby
    # loses that race.
    add_index :merchant_statements, %i[merchant_id period_start period_end currency],
              unique: true, name: "index_merchant_statements_unique_period"
  end
end
