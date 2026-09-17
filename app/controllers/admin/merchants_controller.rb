# Merchants, plus opening and closing one on its behalf.
#
# `open`/`close` are separate actions rather than an `is_open` checkbox on the
# form, because this is the single most important control in the system — a
# merchant marked open that isn't is the most damaging state there is — and it
# must be one click with an audit row, not a form save.
module Admin
  class MerchantsController < Admin::ApplicationController
    def scoped_resource
      Merchant.includes(:merchant_kind, :owner).order(:name)
    end

    # ── DELETE MEANS DISCARD, BECAUSE ONE-WAY DOOR 6 SAYS SO ─────────────────
    #
    # `Merchant` includes `SoftDeletable` and implements `discard_dependents!`
    # to hide its catalog with it — the whole mechanism is built. Administrate's
    # default `destroy` bypassed all of it and called `destroy`, which is a HARD
    # delete, cascading `dependent: :destroy` onto `catalog_categories` and
    # `catalog_items`.
    #
    # MEASURED rather than reasoned: driving `DELETE /admin/merchants/:id`
    # against a merchant with a catalog and no orders removed the row and left
    # **0 catalog items**, and answered 303 as though it had worked.
    #
    # The blast radius was bounded — `has_many :orders, dependent:
    # :restrict_with_error` stops any merchant that has ever traded, so there
    # was never a hole in the books — which makes this a newly onboarded
    # restaurant losing the menu somebody typed in, rather than lost history.
    # Bounded is not the same as intended: the model says discard and the
    # button said destroy.
    # A merchant that HAS traded can be discarded, and that is the improvement
    # rather than a regression. Hard delete was refused for it by
    # `has_many :orders, dependent: :restrict_with_error`, and rightly — it
    # would have orphaned order history. A discard orphans nothing: the row
    # stays, every past order still resolves through it, and the shop simply
    # stops being listed. That is precisely what one-way door 6 exists to
    # allow.
    def destroy
      resource = requested_resource
      snapshot = audit_values(resource.attributes)
      resource.discard!

      log_intervention(
        "merchant.discarded", target: resource,
        # The FULL row, as the generic console delete recorded. The row is no
        # longer destroyed so this is belt and braces — but an audit entry is
        # cheap and the values it holds cannot be added back later.
        before: snapshot,
        after: { deleted_at: resource.deleted_at.to_s },
        details: { catalog_items_hidden: resource.catalog_items.discarded.count }
      )
      redirect_to admin_merchants_path, notice: "#{resource.name} removed. Its menu went with it."
    end

    def open_merchant
      toggle(true, "opened")
    end

    def close_merchant
      toggle(false, "closed")
    end

    def approve
      merchant = requested_resource
      # The approver's NAME, on the row. It was not recorded at all here —
      # `verified_by` points at `users` and the console operator is an
      # `AdminUser`, so the column could only ever be nil. Signing a merchant
      # is the hardest problem in this business and "who signed this one?" is
      # the first question when a deal is disputed.
      merchant.update!(status: :active, verified_at: Time.current, rejection_reason: nil,
                       verified_by_admin_user: current_admin_user)

      log_intervention("merchant.approved", target: merchant, after: { status: "active" })
      redirect_back fallback_location: admin_merchant_path(merchant), notice: "Merchant approved."
    end

    def suspend
      merchant = requested_resource
      reason = params[:reason].presence

      return redirect_back fallback_location: admin_merchant_path(merchant),
                           alert: "A suspension needs a reason." if reason.blank?

      # Closed as well as suspended: a suspended merchant left `is_open` would
      # still look orderable to anything reading that flag alone.
      merchant.update!(status: :suspended, is_open: false, rejection_reason: reason)
      log_intervention("merchant.suspended", target: merchant, after: { status: "suspended" },
                                             details: { reason: reason })
      redirect_back fallback_location: admin_merchant_path(merchant), notice: "Merchant suspended."
    end

    private

    def toggle(open, word)
      merchant = requested_resource
      merchant.update!(is_open: open)

      log_intervention("merchant.#{word}", target: merchant,
                                           before: { is_open: !open }, after: { is_open: open },
                                           details: { on_their_behalf: true })
      redirect_back fallback_location: admin_merchant_path(merchant), notice: "Merchant #{word}."
    end
  end
end
