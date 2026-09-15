# WHO approved this courier, and this merchant — answerable from the record.
#
# `verified_by_id` exists on both tables and points at `users`. But approval
# happens in the Administrate console, where the operator is an `AdminUser` —
# a deliberately separate table, so that a customer's session token can never
# reach the console. An AdminUser cannot be assigned to a `belongs_to` declared
# `class_name: "User"`, so the column could only ever hold nil for the one path
# that actually approves anyone.
#
# CLAUDE.md is explicit that this must not be nil: "Approval is a human
# decision and must carry a name. A nil approver on an approved courier is not
# a valid state — it is how 'who let this person in?' becomes unanswerable."
# One-way door #5 says the same about interventions generally.
#
# `AuditLog` does already record `admin_user`, so the information was not being
# lost — but a question that can only be answered by scanning a log is a
# question nobody asks. This puts it on the row, where the admin console shows
# it beside the approval.
#
# Both tables in one migration because it is one flaw with two instances.
class RecordWhichAdminVerified < ActiveRecord::Migration[8.1]
  def change
    add_reference :courier_profiles, :verified_by_admin_user, foreign_key: { to_table: :admin_users }
    add_reference :merchants, :verified_by_admin_user, foreign_key: { to_table: :admin_users }
  end
end
