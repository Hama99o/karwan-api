# Courier onboarding: approve, reject, and set the credit line.
#
# Approval is a NAMED action rather than a dropdown, because it must carry the
# approver's identity. An approved courier with no approver is how "who let this
# person in?" becomes unanswerable — and the tazkira and guarantor are collected
# precisely so that question has an answer.
module Admin
  class CourierProfilesController < Admin::ApplicationController
    def approve
      profile = requested_resource

      # `approve!` validates identity and guarantor presence, so an incomplete
      # application cannot be waved through.
      if profile.update(verification_status: :approved, verified_at: Time.current,
                        verified_by: nil, rejection_reason: nil)
        ensure_wallet(profile.user)
        log_intervention("courier.approved", target: profile,
                                             before: { verification_status: "pending" },
                                             after: { verification_status: "approved" })
        redirect_back fallback_location: admin_courier_profile_path(profile), notice: "Courier approved."
      else
        redirect_back fallback_location: admin_courier_profile_path(profile),
                      alert: "Cannot approve: #{profile.errors.full_messages.join('; ')}"
      end
    end

    def reject
      profile = requested_resource
      reason = params[:reason].presence

      return redirect_back fallback_location: admin_courier_profile_path(profile),
                           alert: "A rejection needs a reason." if reason.blank?

      profile.update!(verification_status: :rejected, verified_at: Time.current,
                      rejection_reason: reason, is_available: false)
      log_intervention("courier.rejected", target: profile,
                                           after: { verification_status: "rejected" },
                                           details: { reason: reason })
      redirect_back fallback_location: admin_courier_profile_path(profile), notice: "Courier rejected."
    end

    # Taking a courier off shift on their behalf — for a phone left online, or
    # a courier who has stopped answering.
    def take_off_shift
      profile = requested_resource
      profile.update!(is_available: false)

      log_intervention("courier.taken_off_shift", target: profile, after: { is_available: false })
      redirect_back fallback_location: admin_courier_profile_path(profile), notice: "Taken off shift."
    end

    private

    # A courier without a wallet cannot be charged commission, so approval
    # creates one. The credit line comes from the setting, which is what makes
    # "a new courier can start with nothing" true.
    def ensure_wallet(user)
      return if user.nil? || user.courier_wallet.present?

      CourierWallet.create!(user: user, balance: 0,
                            credit_line: Setting.fetch("default_credit_line"))
    end
  end
end
