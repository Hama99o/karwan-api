# The column default was competing with the Setting, and winning silently.
#
# `merchants.commission_rate` carried a database default of 0.125. Two things
# followed, and the second is the one that made the first invisible:
#
#   1. A merchant created without a rate took 0.125 from the SCHEMA, so
#      `Setting.fetch("commission_rate")` was read by nothing at all.
#   2. Worse, `Merchant.new.commission_rate` is 0.125 rather than nil, so the
#      ops console's new-merchant form RENDERS `value="0.125"` and SUBMITS it.
#      Measured on the rig. A callback that applies the standard only when no
#      rate was supplied therefore never fires on the one path it exists for —
#      Hamma9900 onboarding a shop from the console.
#
# Dropping the default makes the form field render EMPTY, which is the honest
# thing for it to say: this shop has not negotiated a rate, so it gets the
# standard. Typing a number still wins, and that is what a negotiated rate is.
#
# `null: false` is kept — every merchant must end up with a rate. The model's
# `apply_standard_commission_rate` supplies it on create, before validation.
# Existing rows are untouched: they hold their own values and one-way door 1
# means nothing may rewrite what a shop already agreed to.
class DropMerchantCommissionRateDefault < ActiveRecord::Migration[8.1]
  def up
    change_column_default :merchants, :commission_rate, from: BigDecimal("0.125"), to: nil
  end

  def down
    change_column_default :merchants, :commission_rate, from: nil, to: BigDecimal("0.125")
  end
end
