class CreateAuditLogs < ActiveRecord::Migration[8.1]
  def change
    # Every money-touching action and every admin intervention: actor, action,
    # before, after, timestamp. Non-negotiable. This surface can change
    # anything about anyone — reassign a rider, cancel an order, credit a
    # wallet — so accountability is the whole point.
    #
    # Append-only, so no updated_at.
    create_table :audit_logs do |t|
      # Nullable = the system did it.
      t.references :actor, null: true, foreign_key: { to_table: :users }
      t.integer    :actor_role

      t.string     :action, null: false
      t.references :target, polymorphic: true, null: true

      # before/after rather than a diff: a diff cannot be read back without the
      # code that produced it, and this table outlives that code.
      t.jsonb      :before
      t.jsonb      :after
      t.jsonb      :details
      t.string     :ip

      t.datetime   :created_at, null: false
    end

    add_index :audit_logs, :action
    add_index :audit_logs, :created_at
  end
end
