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
