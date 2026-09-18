module Admin
  class UsersController < Admin::ApplicationController
    def restore
      restore_resource(admin_users_path)
    end

    def scoped_resource
      User.includes(:user_roles).order(created_at: :desc)
    end

    # Suspending an account is a named action so it carries a reason and an
    # audit row. A form edit of `status` would record neither.
    def suspend
      user = requested_resource
      user.update!(status: :suspended)

      log_intervention("user.suspended", target: user, after: { status: "suspended" },
                                         details: { reason: params[:reason] })
      redirect_back fallback_location: admin_user_path(user), notice: "Account suspended."
    end

    def reinstate
      user = requested_resource
      user.update!(status: :active)

      log_intervention("user.reinstated", target: user, after: { status: "active" })
      redirect_back fallback_location: admin_user_path(user), notice: "Account reinstated."
    end
  end
end
