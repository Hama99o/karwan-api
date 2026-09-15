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

      # `approve!` rather than `update` — it does all THREE things approval
      # means (status, role, wallet) in one transaction. This used to update
      # the status here and create the wallet separately, and never granted the
      # courier ROLE at all: the courier was "approved", saw no jobs because
      # `CourierScope` resolved to none, and could not even switch into the
      # courier tab. Two of three is a support call nobody can diagnose.
      #
      # It also validates identity and guarantor presence, so an incomplete
      # application cannot be waved through — and `missing_for_approval` says
      # what is outstanding before anyone tries.
      unless profile.ready_for_approval?
        return redirect_back fallback_location: admin_courier_profile_path(profile),
                             alert: "Cannot approve — still missing: #{profile.missing_for_approval.join(', ')}"
      end

      begin
        profile.approve!(by: current_admin_user)
        log_intervention("courier.approved", target: profile,
                                             before: { verification_status: "pending" },
                                             after: { verification_status: "approved" })
        redirect_back fallback_location: admin_courier_profile_path(profile), notice: "Courier approved."
      rescue ActiveRecord::RecordInvalid => e
        redirect_back fallback_location: admin_courier_profile_path(profile),
                      alert: "Cannot approve: #{e.record.errors.full_messages.join('; ')}"
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

    # The wallet lives in `CourierProfile#approve!` now, with the role and the
    # status, in one transaction — a courier approved with two of the three
    # cannot work and cannot be told why.
  end
end
