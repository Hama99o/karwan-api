# Applying to be a courier. THE ONLY WAY A COURIER CAN COME INTO EXISTENCE.
#
# ── Why this is not under Couriers::BaseController ────────────────────────
# That base requires an APPROVED profile and a wallet. An applicant has
# neither, so inheriting it would make applying impossible for exactly the
# people who need to apply — the chicken-and-egg that left this endpoint
# missing and made `admin/courier_profiles` an index over a table nothing could
# write to.
#
# ── Why courier registration looks nothing like a customer's ──────────────
# Hamma9900, R8: "registration for restaurant and rider is very different than
# client — client can be simple but not rider and restaurant." CLAUDE.md says
# why: a courier advances our merchants' food out of their own pocket and
# carries our cash, so they need identity, a guarantor, documents and a human
# approval with a name attached — and "none of it can be collected after the
# fact."
#
# A customer, by contrast, is a phone and an OTP (correction 10). Same app,
# same account, completely different door.
#
# ── Built up over several attempts, on purpose ────────────────────────────
# `create` and `update` accept a PARTIAL application. A courier fills this in
# on a cheap phone on a bad connection, and refusing the whole form because one
# 4 MB tazkira photo timed out is how an application is abandoned. Completeness
# is enforced at APPROVAL, by a human, in the admin console — `approve!` cannot
# pass without the identity fields and the documents.
class Api::V1::Couriers::RegistrationsController < Api::V1::BaseController
  # Photos, on an Afghan connection. Generous, and still a ceiling: this is the
  # one endpoint in the app that accepts megabytes, so an unthrottled version is
  # somebody filling the VPS disk — which is at 90%.
  throttle to: 40, within: 1.hour, by: :user, only: %i[create update]

  def show
    profile = current_user.courier_profile

    # Not an error — most people have never applied. A 404 here would have the
    # app render a failure where the correct screen is the empty form.
    if profile.nil?
      skip_authorization
      return render_ok({ registration: nil })
    end

    authorize profile, :show?
    render_blue(Couriers::RegistrationSerializer, profile)
  end

  def create
    existing = current_user.courier_profile
    # Idempotent rather than a 409: a retry on a bad connection must not be
    # punished, and "you have already applied" is not something to make a
    # courier resolve on their own.
    return update_existing(existing) if existing.present?

    authorize CourierProfile.new(user: current_user), :create?

    profile = CourierProfile.new(user: current_user)
    profile.assign_attributes(registration_params)
    attach_documents(profile)

    return render_unprocessable_entity(profile) unless profile.save

    AuditLog.record!(action: "courier.applied", actor: current_user, actor_role: :customer,
                     target: profile, after: { verification_status: profile.verification_status })

    render_blue(Couriers::RegistrationSerializer, profile, status: :created)
  end

  # Amending an application — including a REJECTED one.
  #
  # A rejected courier must be able to fix what was wrong and resubmit, or one
  # typo in a guarantor's number ends their application permanently and they
  # are lost to a competitor. Resubmitting returns the profile to `pending` so
  # it reappears in the admin queue.
  def update
    profile = current_user.courier_profile
    if profile.nil?
      # `skip_authorization`, or `verify_authorized` raises on the way out and
      # turns an honest 404 into a 500 — the same trap the merchant reject
      # action hit, recorded in docs/NOTES.md. There is nothing to authorise
      # when there is no record.
      skip_authorization
      return render_not_found
    end

    update_existing(profile)
  end

  private

  def update_existing(profile)
    authorize profile, :update?

    # An APPROVED courier must not quietly rewrite the identity a human
    # approved. Changing a tazkira number after approval is the shape of fraud
    # this whole flow exists to prevent, so it goes back to a human.
    was_approved = profile.verification_approved?

    profile.assign_attributes(registration_params)
    attach_documents(profile)
    profile.verification_status = :pending if was_approved || profile.verification_rejected?
    profile.rejection_reason = nil if profile.verification_pending?

    return render_unprocessable_entity(profile) unless profile.save

    if was_approved
      AuditLog.record!(action: "courier.reopened_application", actor: current_user,
                       actor_role: :courier, target: profile,
                       before: { verification_status: "approved" },
                       after: { verification_status: "pending" },
                       details: { note: "the courier edited an approved profile; needs a human" })
    end

    render_blue(Couriers::RegistrationSerializer, profile.reload)
  end

  # TOLERANT OF AN ABSENT `registration` KEY, because a submission may carry
  # nothing but a file.
  #
  # `params.require(:registration)` raised on a documents-only PATCH — which is
  # the single most likely shape of request this endpoint receives, since the
  # whole design is "fill it in over several attempts on a bad connection".
  # The form fields go up once; the three photos go up one at a time as each
  # upload survives.
  def registration_params
    return ActionController::Parameters.new.permit! if params[:registration].blank?

    params.require(:registration).permit(
      :full_name, :father_name, :national_id_number, :guarantor_name,
      :guarantor_phone, :guarantor_relation, :work_area, :plate_number,
      :vehicle_type, accepted_job_kinds: []
    )
  end

  # Attached one at a time and only when present, so a submission carrying one
  # photo does not wipe the two that already landed.
  def attach_documents(profile)
    %i[id_document selfie vehicle_photo].each do |name|
      file = params[name]
      profile.public_send(name).attach(file) if file.present?
    end
  end
end
