require "administrate/base_dashboard"

# ONE-WAY DOOR #3, on screen: who moved this job, from what to what, and when.
# "How long do orders sit in preparing" is the metric that runs a delivery
# business and it cannot be backfilled, so this is the page that proves it is
# being recorded. Polymorphic across `Order` and `Trip`.
#
# Not routed — it is rendered inside an order or a trip.
class StatusTransitionDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    subject: Field::Polymorphic,
    from_status: Field::String,
    to_status: Field::String,
    actor: Field::BelongsTo.with_options(class_name: "User"),
    # The ops console's operator, who is an `AdminUser` and can never be
    # `actor`. Before this column existed the console had nowhere to record
    # itself, so an operator's cancellation was stored — and shown here — as an
    # empty actor, which is what the system's own transitions look like.
    admin_user: Field::BelongsTo.with_options(class_name: "AdminUser"),
    actor_role: Field::String,
    # One column that answers "who", for the list rendered inside an order.
    # Same method and same order as `AuditLog#author`, so an intervention reads
    # identically in the audit log and in the job's own history.
    author: Field::String,
    reason: Field::Text,
    # Where the courier was when they made the move, with the fix's age — the
    # evidence `REALTIME_AND_SCALE.md` §4 says settles "the food never
    # arrived". Blank for moves the courier did not make.
    courier_position: Field::String,
    created_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[from_status to_status author actor_role courier_position created_at].freeze
  SHOW_PAGE_ATTRIBUTES = %i[subject from_status to_status actor admin_user actor_role
                            reason courier_position created_at].freeze
  # An editable history is not a history.
  FORM_ATTRIBUTES = [].freeze

  def display_resource(transition)
    "#{transition.from_status.presence || '—'} → #{transition.to_status}"
  end
end
