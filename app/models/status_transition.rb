# Append-only. Who moved this job, from what, to what, when, and why.
#
# Polymorphic over Order and Trip, which is why the statuses are STRINGS rather
# than an integer enum: the two have different vocabularies, and integer 3 would
# mean `ready` for a food order and something unrelated for a trip. One column
# cannot carry two enums.
#
# Strings are also the better choice for an append-only log on their own merits.
# An integer whose meaning lives in a constant someone may reorder is exactly
# what becomes unreadable a year later, when the question being asked is "what
# happened to this order in March".
#
# TWO KINDS OF ACTOR, the shape `audit_logs` already uses and for its reason:
# there are two answers to "who did this" — an app user (a courier failing a
# job, a customer cancelling) or a staff member in the ops console, who is an
# `AdminUser` and not a `User`.
#
# Both nil means the SYSTEM did it — a timeout fired. That distinction is the
# difference between "the merchant rejected it" and "the merchant never
# answered", and support needs to know which.
#
# It used to be `actor_id.nil?` alone, and the console could not satisfy it:
# `Admin::OrdersController` passed `actor: nil` because it had nowhere to put
# its operator, so a human cancelling an order was recorded as a machine and
# the customer was told so. One nil carried two opposite meanings.
class StatusTransition < ApplicationRecord
  enum :actor_role, Roles::ALL, prefix: :by

  belongs_to :subject, polymorphic: true
  belongs_to :actor, class_name: User.name, optional: true
  belongs_to :admin_user, optional: true

  validates :to_status, presence: true
  validate  :statuses_belong_to_the_subject

  scope :chronological, -> { order(:created_at) }

  # NO HUMAN AT ALL — neither an app user nor an operator. Both columns, not
  # one: a console intervention has no `actor_id` and is not the system.
  def system?
    actor_id.nil? && admin_user_id.nil?
  end

  # Who it was, however it is spelled. Same method and same order as
  # `AuditLog#author`, so the two logs answer the question identically.
  def author
    admin_user&.to_s || actor&.display_name || "system"
  end

  private

  # Integrity without an enum. The subject class already declares its own
  # STATUSES, so that is what these are checked against — which also means a
  # third demand type needs no change here.
  def statuses_belong_to_the_subject
    known = subject_class_statuses
    return if known.blank?

    [ [ :from_status, from_status ], [ :to_status, to_status ] ].each do |field, value|
      next if value.blank?
      next if known.include?(value.to_s)

      errors.add(field, "#{value.inspect} is not a status of #{subject_type}")
    end
  end

  def subject_class_statuses
    return nil if subject_type.blank?

    klass = subject_type.safe_constantize
    return nil unless klass.respond_to?(:statuses)

    klass.statuses.keys.map(&:to_s)
  end
end
