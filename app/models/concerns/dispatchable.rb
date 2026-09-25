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
    scope :newest_first, -> { order(created_at: :desc, id: :desc) }
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

    # ── THE PROBLEM REASONS THE COURIER APP IS OFFERED ────────────────────
    #
    # All of them except the ones the app cannot yet LABEL. `problem_reasons`
    # is a list of bare keys the app translates itself, so a new key reaches a
    # courier as the raw string `fake_note` on his problem sheet until the app
    # ships its words. So a new reason is recorded and counted from day one,
    # and OFFERED only once `fake_note_reason_offered` is switched on — which
    # the mobile side does in the same release as its labels.
    #
    # The serializer and `couriers/jobs#problem` both read this, so the sheet
    # and the endpoint cannot disagree. The console's "mark failed" offers every
    # reason: an operator hearing it on the phone is not waiting for a label.
    def offered_failure_reasons
      held_back = Setting.fetch("fake_note_reason_offered") ? [] : %w[fake_note]
      failure_reasons.keys - held_back
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

  # ── WAS A PIN OFF THE ROAD NETWORK WHEN THIS WAS ORDERED? ────────────────
  #
  # Computed from the snap distances FROZEN on this row at quote time, not from
  # asking the router again. Re-querying would answer about today's map and
  # today's pin, and correction 13's frozen-amount discipline is exactly that
  # every input is written down at the moment it is quoted rather than
  # recomputed for display.
  #
  # `Routing::Route#pin_far_from_road?` asks the same question of a live quote.
  # This asks it of an order that has already been placed, which is when it
  # matters: the customer's tracking screen already carries the copy — "a
  # courier may not find this from the pin alone" — and has never been wired to
  # the signal.
  def pin_far_from_road?
    threshold = Setting.fetch("routing_snap_warning_metres")

    [ origin_snap_metres, destination_snap_metres ].compact.any? { |metres| metres > threshold }
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
  # `admin_user` is the ops console's operator, who is an `AdminUser` and can
  # never be `actor`. Defaulted rather than required because every in-app path
  # has a real `actor` and none of them has one.
  def transition_to!(to_status, actor:, actor_role:, reason: nil, admin_user: nil)
    return false unless can_transition_to?(to_status, actor_role: actor_role)

    from = status
    moved = false
    transaction do
      # ── TWO MOVES AT ONCE: THE SECOND ONE SEES THE FIRST ──────────────────
      #
      # `can_transition_to?` reads THIS copy's status, so two requests that
      # loaded the job together both passed it. Reproduced 2026-09-24: a
      # shop's accept pressed twice wrote two `accepted` rows, and the second
      # request died on the offers' unique sequence index — a 500 on the
      # tablet for an order that had in fact been accepted. The courier's
      # "delivered" did the same until 3c731d3.
      #
      # So the row is locked and its STORED status compared with ours. The
      # second request waits here for the first to commit, then finds the
      # status moved and is refused like any stale client. Read with `pick`,
      # not `lock!`: `lock!` reloads, and would throw away anything the caller
      # set on this record before asking to move it.
      next unless self.class.lock.where(id: id).pick(:status) == from

      update!(status: to_status, "#{to_status}_at": Time.current)
      transitions.create!(
        from_status: from, to_status: to_status.to_s,
        actor: actor, admin_user: admin_user, actor_role: actor_role, reason: reason,
        **courier_position_at_the_moment(actor, actor_role)
      )
      # A job that has ENDED can't still be on offer. Until 25 Sept 2026 a
      # console cancel (or a timeout, or a failure) left the live offer
      # pending, so the courier's poll showed an offer for a dead job until it
      # ran out. Withdrawn here, whoever ended it, with a real time on it
      # (a bulk update skips updated_at) so Couriers::LastOffer can say so.
      offers.status_offered.update_all(status: Offer.statuses[:superseded], updated_at: Time.current) if terminal?
      moved = true
    end
    moved
  end
  private

  # ── WHERE THE COURIER WAS WHEN THEY SAID SO ───────────────────────────────
  #
  # `REALTIME_AND_SCALE.md` §4: the position at picked up and delivered *"is
  # the only evidence when a customer says the food never arrived"* — and
  # `courier_profiles` overwrites it seconds later, by design. So it is copied
  # here, at the moment, for every move the COURIER makes.
  #
  # Only the courier's own moves. An operator failing an order on the phone, or
  # a timeout, is not a claim the courier made at a place; putting his position
  # on it would read as though he had.
  #
  # The fix is recorded WITH ITS OWN TIME, even when it is older than
  # `CourierProfile::STALE_AFTER`. Staleness is a dispatch rule — never offer
  # work from where somebody was an hour ago — and not an evidence rule: an old
  # fix with its age attached is still the last thing known, and dropping it
  # would make "no fix at all" and "an old fix" the same nil.
  def courier_position_at_the_moment(actor, actor_role)
    return {} unless actor_role.to_s == "courier"

    profile = actor&.courier_profile
    return {} unless profile&.coordinates

    { courier_latitude: profile.last_latitude, courier_longitude: profile.last_longitude,
      courier_located_at: profile.location_updated_at }
  end

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
