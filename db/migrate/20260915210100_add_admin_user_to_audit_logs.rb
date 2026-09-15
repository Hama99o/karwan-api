class AddAdminUserToAuditLogs < ActiveRecord::Migration[8.1]
  # An intervention in the ops console is made by an AdminUser, not by a `User`.
  # `actor_id` already records app-side actors (a courier failing a job, a
  # customer cancelling); this records the staff member.
  #
  # Both nullable, and a row may carry either: "who did this" has two possible
  # kinds of answer and collapsing them into one polymorphic column would make
  # the common query — "everything this admin did" — a type check.
  def change
    add_reference :audit_logs, :admin_user, null: true, foreign_key: true
  end
end
