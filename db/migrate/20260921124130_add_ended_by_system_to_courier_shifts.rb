# HOW A SHIFT ENDED, not only when.
#
# A shift closed because the courier tapped "off" is an OBSERVED end. One closed
# because their app went silent is an INFERRED one, and the two must not read
# the same — a report that cannot tell them apart is quoting inference as
# evidence, which is the failure this project keeps finding.
#
# Default false: every end recorded before this column existed was a real
# toggle, because nothing else could close a shift.
class AddEndedBySystemToCourierShifts < ActiveRecord::Migration[8.1]
  def change
    add_column :courier_shifts, :ended_by_system, :boolean, null: false, default: false
  end
end
