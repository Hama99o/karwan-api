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
    actor_role: Field::String,
    reason: Field::Text,
    created_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[from_status to_status actor_role created_at].freeze
  SHOW_PAGE_ATTRIBUTES = %i[subject from_status to_status actor actor_role reason created_at].freeze
  # An editable history is not a history.
  FORM_ATTRIBUTES = [].freeze

  def display_resource(transition)
    "#{transition.from_status.presence || '—'} → #{transition.to_status}"
  end
end
