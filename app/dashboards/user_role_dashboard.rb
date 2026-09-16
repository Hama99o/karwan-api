require "administrate/base_dashboard"

# WHICH HATS THIS PERSON HOLDS — one row per role, which is the thing that
# actually grants permission. `users.last_active_role` is only which hat they
# last chose, and `user_sessions.active_role` is which one a given device is
# wearing; neither grants anything.
#
# Not routed: roles are granted by the intervention endpoints, which log who
# did it. A generic CRUD form could never record that.
class UserRoleDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    user: Field::BelongsTo,
    role: Field::String,
    created_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[role created_at].freeze
  SHOW_PAGE_ATTRIBUTES = %i[user role created_at].freeze
  FORM_ATTRIBUTES = [].freeze

  def display_resource(user_role)
    user_role.role
  end
end
