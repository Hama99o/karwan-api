# Base controller for every Administrate screen.
#
# Security posture, stated because this surface can cancel any order, credit any
# wallet and approve any courier:
#
#   * authenticate_admin_user! — no page is reachable without a valid admin
#     session. AdminUser is a separate table from the mobile User, so a customer
#     or courier token can never reach here.
#   * protect_from_forgery — the host app runs `config.api_only = true`, which
#     disables Rails' default CSRF protection. Admin pages submit HTML forms
#     backed by a browser session, so it is re-enabled explicitly.
#   * every intervention writes an audit row naming the admin who did it. That
#     is a one-way door in CLAUDE.md, and this is where it becomes visible.
module Admin
  class ApplicationController < Administrate::ApplicationController
    protect_from_forgery with: :exception

    before_action :authenticate_admin_user!

    private

    # Records a staff action. Failures here must never break the action itself
    # — but they are logged rather than swallowed, because an audit trail that
    # silently stops is worse than one that was never claimed.
    def log_intervention(action, target: nil, before: nil, after: nil, details: nil)
      AuditLog.record!(
        action: action, admin_user: current_admin_user, actor_role: :admin,
        target: target, before: before, after: after, details: details,
        ip: request.remote_ip
      )
    end

    # Administrate's default is 20; an ops console watching a busy evening
    # wants more of the board on one screen.
    def records_per_page
      params[:per_page] || 50
    end
  end
end
