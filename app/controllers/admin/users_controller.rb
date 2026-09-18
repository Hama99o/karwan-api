module Admin
  class UsersController < Admin::ApplicationController
    # ── A LOST PHONE IS NOT A TIDINESS PROBLEM ──────────────────────────
    #
    # In a cash business somebody holding a courier's phone can go on shift as
    # that courier and collect our money. Revoking is the only remedy and there
    # was no path to it — `UserSession#revoke!` existed and nothing called it
    # from the console.
    #
    # REVOKE, NEVER DISPLAY. The console shows how many sessions are live and
    # never a `token_digest`: a screen that prints one is a screen that leaks a
    # working session.
    def revoke_sessions
      user = requested_resource
      live = user.user_sessions.live.to_a

      if live.empty?
        return redirect_back fallback_location: admin_user_path(user),
                             notice: "No live sessions to revoke."
      end

      live.each(&:revoke!)

      log_intervention("user.sessions_revoked", target: user,
                                                before: { live_sessions: live.size },
                                                after: { live_sessions: 0 },
                                                details: { platforms: live.map(&:platform).tally })
      redirect_back fallback_location: admin_user_path(user),
                    notice: "Revoked #{live.size} session(s). They will have to sign in again."
    end

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
