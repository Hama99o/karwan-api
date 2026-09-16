# WHICH MODE THE APP IS IN IS A FACT ABOUT A DEVICE, NOT ABOUT A PERSON.
#
# `users.active_role` meant one human had one mode everywhere. But the same
# human runs a merchant tablet on the counter and a phone in his pocket, and a
# courier who swaps to a second phone when the first one dies keeps both
# signed in. Switching to the customer tab on the phone flipped the tablet's
# tab too, on its next launch — one account, several devices, one shared hat.
#
# So the live fact moves to the session, which is exactly the scope the request
# already resolves: `Authenticatable` looks up a `UserSession` per request and
# can read the mode from it with no extra query.
#
# The column on `users` is NOT dropped, it is RENAMED to `last_active_role`,
# because it was doing a second job that is still wanted: remembering where
# someone left off. `MeController#switch_role` says why in its own comment — a
# reinstall must not drop a courier back into the customer tab, and a reinstall
# is a NEW session, so a session-only role would forget. Two columns, two
# meanings, both named for what they are:
#
#   users.last_active_role       — a PREFERENCE. Seeds the next new session.
#   user_sessions.active_role    — the FACT. What this device is showing now.
class MoveActiveRoleToUserSessions < ActiveRecord::Migration[8.1]
  def up
    # Defaults to customer (0) so a session issued by any path is never
    # role-less, and `current_role` can never be nil for a signed-in request.
    add_column :user_sessions, :active_role, :integer, null: false, default: 0

    # Every session that exists inherits the hat its owner was wearing. Without
    # this, everyone already signed in is silently moved to the customer tab —
    # and couriers mid-shift are exactly the people who would notice.
    execute <<~SQL
      UPDATE user_sessions
         SET active_role = users.active_role
        FROM users
       WHERE users.id = user_sessions.user_id
    SQL

    rename_column :users, :active_role, :last_active_role
  end

  def down
    rename_column :users, :last_active_role, :active_role
    remove_column :user_sessions, :active_role
  end
end
