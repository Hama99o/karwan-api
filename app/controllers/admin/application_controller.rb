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

    # ── THE POLICIES WERE WRITTEN, CORRECT, AND NEVER CONSULTED ───────────
    #
    # Found by the caller sweep on 2026-09-18: `CourierWalletPolicy#adjust?`,
    # `#top_up?`, `#settle?` and `CourierProfilePolicy#approve?`, `#reject?`
    # had no caller anywhere. The console enforced the same rule through
    # `authenticate_admin_user!`, so nothing was reachable that should not have
    # been — this is edu-safi's bug with the outcome coinciding.
    #
    # The danger was the reading. A file that says "money only moves through
    # admin: a courier crediting their own wallet is the one thing this design
    # exists to prevent" is the first place anyone looks to CHANGE that rule,
    # and changing it would have done nothing. Wiring it costs no behaviour
    # today — every method is `= admin?` and every console session is an admin —
    # which is exactly what makes it safe to do now and expensive to leave.
    #
    # `pundit_user` is the AdminUser, NOT `current_user`: the console's actor is
    # its own table. Without this the policies would refuse every admin.
    include Pundit::Authorization

    rescue_from Pundit::NotAuthorizedError, with: :deny_intervention

    before_action :authenticate_admin_user!

    # ── EVERY EDIT, NOT ONLY THE INTERVENTIONS ────────────────────────────────
    #
    # `log_intervention` is called by hand from the custom actions — approve,
    # suspend, reassign, credit — so those were audited and Administrate's own
    # create/update/destroy were not. That covered the dramatic actions and
    # missed two of the most consequential edits in the system: changing a
    # `commission_rate`, which changes what a merchant is paid, and reassigning
    # `owner_id`, which changes who controls a restaurant. Both are a plain form
    # save.
    #
    # One-way door #5 says an audit row for every intervention, and
    # "unanswerable later if nobody wrote it" is exactly the failure mode: the
    # row shows the new commission and nothing shows the old one or who typed
    # it.
    #
    # HOOKED HERE so every dashboard inherits it, including ones added later —
    # a per-controller hook is a hook somebody forgets. `create` uses the gem's
    # own block, because Administrate's `create` keeps the record in a local.
    def create
      super do |resource|
        log_console_edit(resource, "created", after: audit_values(resource.attributes))
      end
    end

    def update
      super
      return if requested_resource.previous_changes.blank?

      before, after = audit_diff(requested_resource.previous_changes)
      log_console_edit(requested_resource, "edited", before: before, after: after)
    end

    def destroy
      snapshot = audit_values(requested_resource.attributes)
      super
      return unless requested_resource.destroyed?

      log_console_edit(requested_resource, "deleted", before: snapshot)
    end

    private

    # Noise, and in one case worse than noise: `search_text` is a derived blob
    # that would dominate every audit row it appeared in.
    AUDIT_SKIP = %w[created_at updated_at search_text].freeze

    def log_console_edit(resource, verb, before: nil, after: nil)
      log_intervention(
        "#{resource.model_name.element}.#{verb}",
        target: resource.persisted? ? resource : nil,
        before: before, after: after,
        # The dashboard says which screen it was typed on, which matters when
        # two dashboards can edit the same row.
        details: { via: "console", dashboard: controller_name }
      )
    end

    # `previous_changes` is {attribute => [was, now]}, which is already the
    # before/after this table stores — no diff format to decode later.
    def audit_diff(changes)
      kept = changes.except(*AUDIT_SKIP)
      [
        audit_values(kept.transform_values(&:first)),
        audit_values(kept.transform_values(&:last))
      ]
    end

    def audit_values(attributes)
      attributes.except(*AUDIT_SKIP).transform_values { |value| value.is_a?(BigDecimal) ? value.to_s : value }
    end

    # Records a staff action. Failures here must never break the action itself
    # — but they are logged rather than swallowed, because an audit trail that
    # silently stops is worse than one that was never claimed.
    # ── UNDO, AND WHY IT IS HERE RATHER THAN COPIED INTO EACH CONTROLLER ────
    #
    # The caller sweep found `SoftDeletable#undiscard!` had no caller anywhere:
    # no route, no controller, no dashboard action. One-way door 6 makes a
    # delete recoverable IN THE DATA, and the operator still had to ring a
    # developer — on the console Hamma9900 says five to ten people will work in.
    #
    # Restoring is audited for the same reason discarding is. "An operator can
    # undo a delete" and "nobody can tell who did" are two different states, and
    # only one of them is acceptable on a surface that touches money.
    def restore_resource(redirect_to_path)
      resource = requested_resource

      unless resource.respond_to?(:undiscard!)
        return redirect_back fallback_location: redirect_to_path,
                             alert: "That record cannot be restored."
      end

      # Idempotent, and it says so: an operator who clicks twice, or two
      # operators on the same record, must not see a failure for a thing that
      # is already true.
      if resource.kept?
        return redirect_back fallback_location: redirect_to_path,
                             notice: "That record was not deleted."
      end

      deleted_at = resource.deleted_at
      resource.undiscard!

      log_intervention(
        "#{resource.model_name.singular}.restored", target: resource,
        before: { deleted_at: deleted_at.to_s },
        after: { deleted_at: nil }
      )
      redirect_back fallback_location: redirect_to_path, notice: "Restored."
    end

    def pundit_user
      current_admin_user
    end

    # HTML, not the API's JSON 403 — this surface is a browser session, and an
    # operator needs to land somewhere they can still work.
    def deny_intervention
      redirect_back fallback_location: admin_root_path,
                    alert: "You are not allowed to do that."
    end

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
