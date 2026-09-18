# THE LEDGER COULD NOT NAME AN OPERATOR.
#
# `wallet_entries.recorded_by_id` is a foreign key to `users`, and the console's
# actor is an `AdminUser` — a separate table, because correction 16 removed
# admin from the mobile app entirely. So every entry written by an operator had
# `recorded_by: nil`: wrong table, not an oversight.
#
# The information was never lost — `audit_logs` carries `admin_user_id`, the
# balance before and after, and the `entry_id`. What was lost is the ledger
# being self-describing: a courier's statement, or any reconciliation built from
# `wallet_entries` alone, could not say who made an adjustment without a join.
# In a cash business where "unexplained mismatches are theft", the row a courier
# disputes is exactly the one whose author was a table away.
#
# Additive and nullable, and done NOW rather than later because nothing is
# deployed: there is no historical ledger to migrate or misinterpret, which is
# the window in which a money-table change is cheap. One-way door 4 is about the
# record of record, and the record of record does not exist yet.
class AddRecordedByAdminUserToWalletEntries < ActiveRecord::Migration[8.1]
  def change
    add_reference :wallet_entries, :recorded_by_admin_user,
                  null: true, foreign_key: { to_table: :admin_users }, index: true
  end
end
