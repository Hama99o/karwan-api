class RecordTheOperatorOnAStatusTransition < ActiveRecord::Migration[8.1]
  # ── THE CONSOLE HAD AN OPERATOR AND NOWHERE TO PUT THEM ──────────────────
  #
  # `status_transitions.actor_id` references `users`. The ops console is signed
  # in as an **`AdminUser`**, a different table, so every console intervention
  # passed `actor: nil` — and `StatusTransition#system?` reads a nil actor as
  # "a machine did it". A human cancelling an order from the console was
  # therefore recorded, and reported to the customer, as the system.
  #
  # `audit_logs` already carries both columns and states the reason: *"Two
  # kinds of actor, because there are two kinds of answer to 'who did this': an
  # app user or a staff member in the ops console."* This gives the append-only
  # table with the stronger claim on it — one-way door 3, *"record the actor
  # too"* — the same shape, so `system?` can mean **no human at all**.
  #
  # ADDITIVE AND NULLABLE. It changes no existing row: the transitions already
  # written by the console keep their nil actor and stay indistinguishable from
  # a timeout, which is exactly the information that was never captured and
  # cannot be invented now. Only rows written from here on can answer.
  def change
    add_reference :status_transitions, :admin_user, null: true, index: true
  end
end
