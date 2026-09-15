# What a food order and a passenger trip genuinely have in common.
#
# Both are a job offered to a courier with a deadline, moving through a state
# machine where every step must name who moved it, ending in cash that has to be
# tracked until it reaches us. None of that is specific to food.
#
# The including class supplies four constants, because the vocabularies differ:
#   STATUSES    — name => integer, for the enum
#   TRANSITIONS — state => { next_state => [roles allowed to make the move] }
#   TERMINAL    — the states with no way out
#   TIMEOUTS    — state => duration it may sit there
#
# Keeping them as class constants rather than a shared table is what lets a trip
# have `arrived` and an order have `preparing` without either pretending to
# understand the other.
module Dispatchable
  extend ActiveSupport::Concern

  included do
    has_many :offers, as: :offerable, dependent: :destroy
    has_many :transitions, as: :subject, class_name: StatusTransition.name, dependent: :destroy

    # Polymorphic, so nullify rather than destroy: a ledger row outlives the
    # job it was charged for.
    has_many :wallet_entries, as: :source, dependent: :nullify

    # `self` inside a scope lambda is the RELATION, not the class, so
    # `self::STATUSES` raises TypeError — a Relation is not a Module. The
    # constants are reached through a class method instead, which the relation
    # delegates to klass.
    scope :live, -> { where.not(status: terminal_status_values) }
    scope :newest_first, -> { order(created_at: :desc) }
    scope :for_courier, ->(courier) { where(courier: courier) }
    # Money that has not yet reached us, whatever the payment method.
    scope :unsettled, -> { where(payment_status: %i[pending collected]) }
  end

  class_methods do
    def terminal_status_values
      self::STATUSES.values_at(*self::TERMINAL)
    end

    # Every non-terminal state must have a timeout and every terminal state must
    # have none. Asserted in the specs for both classes, because a state with no
    # deadline is how a job is silently abandoned — a person waiting with cold
    # food, or standing on a street corner.
    def states_without_timeout
      (self::STATUSES.keys.map(&:to_sym) - self::TERMINAL) - self::TIMEOUTS.keys
    end
  end

  def terminal?
    self.class::TERMINAL.include?(status.to_sym)
  end

  def allowed_transitions
    self.class::TRANSITIONS.fetch(status.to_sym, {})
  end

  def can_transition_to?(to_status, actor_role:)
    allowed_transitions[to_status.to_sym]&.include?(actor_role.to_sym) || false
  end

  # When the job entered its current state. Each state has its own timestamp
  # column; updated_at is the fallback so this never returns nil.
  def state_entered_at
    column = "#{status}_at"
    (respond_to?(column) ? public_send(column) : nil) || updated_at
  end

  def timeout_for_current_state
    self.class::TIMEOUTS[status.to_sym]
  end

  def overdue?
    timeout = timeout_for_current_state
    return false if timeout.blank?

    state_entered_at + timeout < Time.current
  end

  # Records the move AND who made it. Returns false rather than raising on an
  # illegal transition, so a stale client cannot 500 the endpoint.
  def transition_to!(to_status, actor:, actor_role:, reason: nil)
    return false unless can_transition_to?(to_status, actor_role: actor_role)

    from = status
    transaction do
      update!(status: to_status, "#{to_status}_at": Time.current)
      transitions.create!(
        from_status: from, to_status: to_status.to_s,
        actor: actor, actor_role: actor_role, reason: reason
      )
    end
    true
  end
end
