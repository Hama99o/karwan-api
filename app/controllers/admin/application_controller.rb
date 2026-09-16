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
