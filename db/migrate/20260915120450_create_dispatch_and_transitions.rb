class CreateDispatchAndTransitions < ActiveRecord::Migration[8.1]
  # Shared machinery. Both demand types — a food order and a trip — are offered
  # to a courier with a deadline, and both move through a state machine whose
  # every step must name who moved it. Neither of those is specific to food, so
  # neither table is.
  #
  # This is the whole point of the two-demand-type restructure: the courier
  # pool, the wallet, the commission, the dispatch deadline and the audit trail
  # are one system. Only the demand differs.
  def change
    # Every state change records WHO moved it and WHEN.
    #
    # `from_status` / `to_status` are STRINGS, not an integer enum, and this is
    # deliberate. The table is polymorphic over Order and Trip, which have
    # different status vocabularies — integer 3 would mean `ready` for a food
    # order and something unrelated for a trip, and one column cannot carry two
    # enums. Strings also outlive renumbering: an append-only log whose meaning
    # lives in a constant someone may reorder is exactly what becomes
    # unreadable a year later. `StatusTransition` validates them against the
    # subject's own STATUSES, so integrity does not depend on the enum.
    create_table :status_transitions do |t|
      t.references :subject, polymorphic: true, null: false
      t.string     :from_status
      t.string     :to_status, null: false
      # Nullable actor = the system did it, i.e. a timeout fired. That is the
      # difference between "the restaurant rejected it" and "the restaurant
      # never answered", and support needs to tell them apart.
      t.references :actor, null: true, foreign_key: { to_table: :users }
      t.integer    :actor_role
      t.text       :reason

      t.datetime   :created_at, null: false
    end

    add_index :status_transitions, [ :subject_type, :subject_id, :created_at ],
              name: "index_status_transitions_on_subject_and_time"

    # Dispatch, kept crude on purpose: offer to the nearest available courier
    # whose wallet can fund the job, time out, offer to the next, then surface
    # to admin. No batching, no optimisation, no zones. The manual override is
    # what makes the business operable while the automation is wrong.
    create_table :offers do |t|
      t.references :offerable, polymorphic: true, null: false
      t.references :courier, null: false, foreign_key: { to_table: :users }

      t.integer  :status, null: false, default: 0
      t.integer  :sequence, null: false, default: 1
      t.datetime :offered_at, null: false
      # Every offer has a deadline. An offer with no timeout is how a job sits
      # unassigned while a courier who went home never declines it.
      t.datetime :expires_at, null: false
      t.datetime :responded_at

      t.timestamps
    end

    add_index :offers, [ :offerable_type, :offerable_id, :sequence ], unique: true,
              name: "index_offers_on_offerable_and_sequence"
    add_index :offers, [ :courier_id, :status ]
    add_index :offers, :expires_at
  end
end
