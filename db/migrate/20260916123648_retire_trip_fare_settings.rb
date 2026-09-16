# The four `trip_*` fare keys moved to `pricing_rates`, because a ride fare now
# depends on the vehicle class the passenger chose and a key-value table cannot
# hold that.
#
# The ROWS are deleted, not just the definitions: a dead price key left on the
# Config screen is a number Hamma9900 would type and watch do nothing, and
# "why did changing the fare not change the fare" is the worst possible half
# hour to give him.
#
# Irreversible on purpose — `down` cannot know what he had typed, and guessing
# would restore a default as if it were his. The numbers are in
# `PricingRate::DEFAULTS`, and any value he had set is in the audit log, which
# is exactly what that log is for.
class RetireTripFareSettings < ActiveRecord::Migration[8.1]
  RETIRED = %w[trip_base_fare trip_fare_per_km trip_fare_per_minute trip_minimum_fare].freeze

  def up
    Setting.where(key: RETIRED).delete_all
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "the tariff lives in pricing_rates now; restoring these keys would create a second " \
          "source of truth for a ride fare"
  end
end
