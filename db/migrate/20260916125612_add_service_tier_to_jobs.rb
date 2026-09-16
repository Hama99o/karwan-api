# THE TIER THE CUSTOMER CHOSE — AND THAT CHOICE IS THE CONSENT TO BE BATCHED.
#
# `docs/SERVICE_TIERS_AND_BATCHING.md` §1, which is the idea the whole feature
# turns on: batching is not something done to a customer behind their back, it
# is something they agree to in exchange for a lower price.
#
#   premium — costs more, and the courier carries THAT ORDER ALONE
#   normal  — cheaper, and it may be combined with up to N others
#
# A customer who paid the normal fare and waited longer because the courier
# collected two other orders has no complaint: they chose it and paid less. A
# premium customer is never batched, so there is nothing to explain.
#
# ── WHY THIS COLUMN SHIPS NOW, WHEN BATCHING DOES NOT ─────────────────────
#
# **Consent cannot be retrofitted.** Nobody can ask a past customer whether
# their completed order could have been shared. So a tier without batching is a
# price difference that costs nothing to honour — we simply never batch — while
# batching without a recorded tier is unshippable, because every existing
# order's consent is unknown.
#
# Getting those two in the wrong order is the expensive mistake. This column is
# cheap insurance bought before the thing it insures.
#
# Defaults to `normal` (0), which is the honest default for every row that
# already exists: nothing has been batched, and nobody was charged a premium.
class AddServiceTierToJobs < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :service_tier, :integer, null: false, default: 0
    add_column :trips, :service_tier, :integer, null: false, default: 0

    # Dispatch will ask "may this job join a batch?" on every offer, and the
    # answer is this column plus the status.
    add_index :orders, %i[service_tier status]
    add_index :trips, %i[service_tier status]
  end
end
