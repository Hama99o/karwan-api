# Dispatch picks "who is nearest" from each courier's last fix, which may be up
# to five minutes old (`CourierProfile::STALE_AFTER`) — and a courier moving
# through traffic for five minutes is not where the system thinks he is. Asked
# on 24 Sept 2026 how old those fixes actually are, the answer was that nothing
# recorded it: the offer row kept who was asked and when, not what the choice
# was made from. The transition log has a courier's fix at pickup and delivery,
# never at the moment he was chosen.
#
# So the offer keeps the two things the choice read: the time of the fix, and
# the straight-line distance to the pickup computed from it. Fix age at offer
# is `offered_at - courier_located_at`. Nullable: a record, never a gate.
class RecordTheFixDispatchChoseOn < ActiveRecord::Migration[8.1]
  def change
    add_column :offers, :courier_located_at, :datetime
    add_column :offers, :distance_km, :decimal, precision: 8, scale: 3
  end
end
