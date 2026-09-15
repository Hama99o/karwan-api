require "administrate/base_dashboard"

# Every money-touching action and every intervention: actor, action, before,
# after, timestamp. Non-negotiable, per CLAUDE.md — and read-only here, because
# an editable audit log is not an audit log.
class AuditLogDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    action: Field::String,
    admin_user: Field::BelongsTo,
    actor: Field::BelongsTo.with_options(class_name: "User"),
    actor_role: Field::String,
    target_type: Field::String,
    target_id: Field::Number,
    before: Field::Text,
    after: Field::Text,
    details: Field::Text,
    ip: Field::String,
    created_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[created_at action admin_user actor target_type target_id].freeze
  SHOW_PAGE_ATTRIBUTES = %i[
    action admin_user actor actor_role target_type target_id before after details ip created_at
  ].freeze
  FORM_ATTRIBUTES = [].freeze

  COLLECTION_FILTERS = {
    interventions: ->(resources) { resources.interventions }
  }.freeze

  def display_resource(log)
    "#{log.action} — #{log.author}"
  end
end
