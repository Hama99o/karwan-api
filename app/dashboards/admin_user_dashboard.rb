require "administrate/base_dashboard"

# Staff accounts. Needed as a dashboard even though there is no admin_users
# screen in the navigation: Administrate resolves the dashboard of any
# ASSOCIATED class in order to display it, and every audit row belongs to an
# AdminUser.
#
# No password field anywhere here — Devise owns that, and a password rendered
# into a form on the highest-privilege account in the system is exactly the
# thing not to build. Accounts are created out of band.
class AdminUserDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    name: Field::String,
    email: Field::String,
    sign_in_count: Field::Number,
    current_sign_in_at: Field::DateTime,
    last_sign_in_at: Field::DateTime,
    current_sign_in_ip: Field::String,
    failed_attempts: Field::Number,
    locked_at: Field::DateTime,
    created_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[name email last_sign_in_at locked_at].freeze
  SHOW_PAGE_ATTRIBUTES = %i[
    name email sign_in_count current_sign_in_at last_sign_in_at current_sign_in_ip
    failed_attempts locked_at created_at
  ].freeze
  FORM_ATTRIBUTES = [].freeze

  def display_resource(admin_user)
    admin_user.to_s
  end
end
