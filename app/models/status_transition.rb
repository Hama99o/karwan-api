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
# A nil actor means the system did it — i.e. a timeout fired. That distinction
# is the difference between "the restaurant rejected it" and "the restaurant
# never answered", and support needs to know which.
class StatusTransition < ApplicationRecord
  enum :actor_role, Roles::ALL, prefix: :by

  belongs_to :subject, polymorphic: true
  belongs_to :actor, class_name: User.name, optional: true

  validates :to_status, presence: true
  validate  :statuses_belong_to_the_subject

  scope :chronological, -> { order(:created_at) }

  def system?
    actor_id.nil?
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
