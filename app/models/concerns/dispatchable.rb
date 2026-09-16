# What a food order and a passenger trip genuinely have in common.
#
# Both are a job offered to a courier with a deadline, moving through a state
# machine where every step must name who moved it, ending in cash that has to be
# tracked until it reaches us. None of that is specific to food.
#
# The including class supplies five constants, because the vocabularies differ:
#   STATUSES    — name => integer, for the enum
#   TRANSITIONS — state => { next_state => [roles allowed to make the move] }
#   TERMINAL    — the states with no way out
#   TIMEOUTS    — state => duration it may sit there
#   CODE_PREFIX — the letter a human reads out: K for an order, T for a trip
#
# Keeping them as class constants rather than a shared table is what lets a trip
# have `arrived` and an order have `preparing` without either pretending to
# understand the other.
module Dispatchable
  extend ActiveSupport::Concern

  # ── THE CODE HAS TO WORK ON PAPER ───────────────────────────────────────────
  #
  # Hamma9900: *"they should be able to print if they want, otherwise they can
  # just write the number on paper."* A restaurant with no printer, no charger
  # and a queue at the counter is the NORMAL case, not the degraded one — so
  # printing is the nice-to-have and writing it down must always work.
  #
  # A prefix letter plus six digits: seven characters, said in one breath over a
  # bad line, written with a pen in three seconds. It replaced a prefix plus
  # `yymmdd` plus four digits, eleven characters of which six were a date that
  # told a human nothing — support searches by code, not by day.
  #
  # DIGITS ONLY, which is the whole of SERVICE_TIERS_AND_BATCHING.md §6's
  # unambiguity requirement rather than laziness: every collision it names is
  # between a digit and a LETTER — 0/O, 1/I/l, 5/S, 8/B — and an alphabet with
  # no letters in it cannot have them. A base32 code would be shorter for the
  # same entropy and would reintroduce all four.
  #
  # ONE generator for both job types, because the two had the same eleven-
  # character format duplicated and only one of them got shortened first.
  CODE_DIGITS = 6

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

    # Overdue in SQL, not in Ruby.
    #
    # `#overdue?` per record is correct but the admin board needs the SET, and
    # the board is the screen someone watches all evening. Measured against
    # 20,000 orders: loading every live order and calling `overdue?` on each
    # took 305ms; this scope does it in the database.
    #
    # Built from the TIMEOUTS table so the two cannot disagree — one state, one
    # deadline, defined once. COALESCE to updated_at mirrors
    # `#state_entered_at`, so a row whose state column is somehow nil is still
    # judged rather than silently treated as fresh.
    scope :overdue, -> { where(overdue_condition) }
    scope :newest_first, -> { order(created_at: :desc) }
    scope :for_courier, ->(courier) { where(courier: courier) }
    # Money that has not yet reached us, whatever the payment method.
    scope :unsettled, -> { where(payment_status: %i[pending collected]) }
  end

  class_methods do
    # Arel rather than an interpolated SQL string: the column names come from
    # our own STATUSES keys, but a query builder that formats identifiers into
    # SQL is the pattern brakeman rightly flags, and arel_table quotes them as
    # identifiers instead. Same reasoning as TrigramSearchable.
    def overdue_condition
      table = arel_table

      self::TIMEOUTS.map { |status, duration|
        entered_at = Arel::Nodes::NamedFunction.new(
          "COALESCE", [ table[:"#{status}_at"], table[:updated_at] ]
        )

        table[:status].eq(self::STATUSES.fetch(status)).and(entered_at.lt(duration.ago))
      }.reduce(:or)
    end

    # The demand type couriers opt into for this kind of job. Each including
    # class declares JOB_KIND; this keeps the lookup off the call site.
    def job_kind
      self::JOB_KIND
    end

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
  private

  # One million codes and a retry loop against the unique index. At Kabul
  # volumes a second attempt is rare and a third will not happen; the index is
  # what guarantees uniqueness, and this loop only avoids showing a customer an
  # error when it fires.
  def assign_code
    self.code ||= loop do
      digits = SecureRandom.random_number(10**Dispatchable::CODE_DIGITS)
      candidate = "#{self.class::CODE_PREFIX}#{digits.to_s.rjust(Dispatchable::CODE_DIGITS, '0')}"
      break candidate unless self.class.exists?(code: candidate)
    end
  end
end
