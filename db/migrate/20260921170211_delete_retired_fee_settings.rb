# Two rows on the Config screen that nothing could read.
#
# `delivery_fee` and `courier_fee` are from the single-fee era. Correction 13
# replaced the delivery fee with a two-part tariff — `delivery_base_fee` +
# (`delivery_fee_per_km` × distance), floored at `delivery_minimum_fee` — and the
# courier's cut became `courier_fee` ON THE ORDER ROW, frozen at quote time,
# rather than a global. Neither key is in `Setting::DEFINITIONS` any more, so
# `Setting.fetch` raises `KeyError` on both: they were not merely unused, they
# were UNREADABLE.
#
# They stayed listed and editable, under the two names Hamma9900 would look for
# first. `setting.rb` records the same lesson about the keys it had already
# removed: *"a dead price key on the Config screen is a number Hamma9900 would
# type and watch do nothing."* These two were missed by that pass.
#
# NAMED EXPLICITLY rather than swept by `WHERE key NOT IN (DEFINITIONS)`. A
# migration is a permanent record of one moment, and a sweep written against a
# constant deletes whatever that constant happens to exclude on the day it runs
# — including, on some future deploy, a row somebody had just added. This
# removes two keys and says which.
#
# The Config screen is also now scoped to readable keys, so a third cannot be
# reached even if it survives. Both, deliberately: this cleans the data, that
# stops it recurring.
class DeleteRetiredFeeSettings < ActiveRecord::Migration[8.1]
  RETIRED = %w[delivery_fee courier_fee].freeze

  def up
    execute ActiveRecord::Base.sanitize_sql_array(
      [ "DELETE FROM settings WHERE key IN (?)", RETIRED ]
    )
  end

  # Irreversible on purpose. Recreating a row nothing reads would put the dead
  # keys back on the Config screen, which is the defect rather than the state
  # worth restoring.
  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
