# A session with no expiry never expires, which is the one thing
# `AFGHAN_UX.md` §7 asks of this table: *"Sessions expire. Do not keep someone
# logged in forever on a device that isn't theirs."* §7 is not hypothetical
# here — *"A phone in a household may be used by several people."*
#
# `UserSession.issue!` has always set `expires_at`, and the factory and seeds do
# too, so no row like this exists (measured: 0 of 258 on the rig). What existed
# was the POSSIBILITY, and `scope :live` went out of its way to honour it —
# `where(expires_at: [ nil, Time.current.. ])` treats a null as live forever,
# with no comment, in a file where everything else has one.
#
# A permissive branch nothing can reach is not harmless: it is the branch a
# migration, a console fix or an import walks into later, and the failure is an
# immortal session on a shared handset. The column is the cheapest place to make
# it impossible.
class RequireASessionExpiry < ActiveRecord::Migration[8.1]
  def up
    # Fail loudly rather than inventing an expiry for a row whose provenance is
    # unknown: a session nobody can account for should be looked at, not
    # silently given ninety days.
    orphans = execute("SELECT COUNT(*) FROM user_sessions WHERE expires_at IS NULL").first["count"].to_i
    raise "#{orphans} sessions have no expires_at — decide what they are before making the column NOT NULL" if orphans.positive?

    change_column_null :user_sessions, :expires_at, false
  end

  def down
    change_column_null :user_sessions, :expires_at, true
  end
end
