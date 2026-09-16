# "I HAVE A RESTAURANT." The front door for a shop.
#
# ── Why it writes a `merchants` row and not a leads table ─────────────────
# A lead IS a merchant awaiting verification: the same row in an earlier state.
# `merchants` already carries `owner_phone`, `owner_name` and a verification
# status, and the console already has a merchants index that Hamma9900 watches
# — so this needs no new surface, no new dashboard and no schema change beyond
# one enum value. Onboarding is then CONTINUOUS: he calls them, fills in the
# rest of the same row, assigns the owner, and `Merchant#sync_owner_role`
# grants the role.
#
# ── Why it is not under Merchants::BaseController ─────────────────────────
# That base resolves a merchant from `owner_id` and refuses without one. An
# applicant has no merchant — that is what they are asking for. Same
# chicken-and-egg as courier registration, documented at the top of
# `couriers/registrations_controller.rb`.
#
# ── WHY IT DOES NOT SET `owner_id` ────────────────────────────────────────
# Assigning an owner GRANTS the merchant role (`sync_owner_role`), and
# `Merchants::BaseController` resolves the board from `owner_id` alone. Setting
# it here would hand a merchant board to anyone who typed a shop name into a
# form. The applicant's phone goes in `owner_phone`, which is how Hamma9900
# finds their account when he calls — and the phone IS the identity, so that is
# enough. A human assigns the owner, after speaking to them.
#
# ── Why a lead and not a signup ───────────────────────────────────────────
# PRODUCT.md: merchants are not self-serve in v0. A commission rate, a pin and
# a set of terms are agreed with a human, and Hamma9900 agrees them himself, in
# person. So the honest thing is to take a name and a phone and say he will
# call — and to say it plainly, because a dead end here is a shop that never
# opens. IDENTITY_AND_ROLES.md §5: a rider applies and waits for approval; a
# restaurant leaves their details and gets a phone call. Neither is an error.
class Api::V1::MerchantApplicationsController < Api::V1::BaseController
  # A handful of short strings, submitted once. No photos here, unlike courier
  # registration, so this can be tight.
  throttle to: 10, within: 1.hour, by: :user, only: :create

  def show
    application = current_application

    # Not an error — almost nobody has applied. A 404 would have the app render
    # a failure where the correct screen is the empty form.
    if application.nil?
      skip_authorization
      return render_ok({ merchant_application: nil })
    end

    authorize application, :show_application?

    render_blue(Shared::MerchantApplicationSerializer, application)
  end

  # Re-submitting UPDATES an open lead rather than adding a second row, so a
  # retry on a bad connection does not put the same shop on the call list
  # twice. Once somebody has been called the row is no longer a lead, and a
  # further submission is a second shop — which is a real thing, because one
  # person can own two.
  def create
    application = current_application
    application = new_lead if application.nil? || !application.status_lead?

    authorize application, :apply?

    application.assign_attributes(application_params)

    if application.save
      render_blue(Shared::MerchantApplicationSerializer, application,
                  status: application.previously_new_record? ? :created : :ok)
    else
      render_unprocessable_entity(application)
    end
  end

  private

  def current_application
    Merchant.kept
            .where(owner_phone: current_user.phone).or(Merchant.kept.where(owner_id: current_user.id))
            .order(created_at: :desc).first
  end

  def new_lead
    Merchant.new(
      status: :lead,
      # THE IDENTITY LINK, from the session and never from the request.
      owner_phone: current_user.phone,
      owner_name: current_user.name,
      # A shop nobody has spoken to is not open, whatever the form says.
      is_open: false
    )
  end

  # `phone` is the SHOP's number and defaults to theirs: a landline is not the
  # owner's mobile, and the number to call about the shop is the useful one.
  # Everything money — commission, terms, the pin, the status — is agreed with a
  # human and is not in this form.
  def application_params
    permitted = params.require(:merchant_application)
                      .permit(:name, :merchant_kind_id, :phone, :landmark_note, :owner_name)
    permitted[:phone] = current_user.phone if permitted[:phone].blank?
    permitted[:owner_name] = current_user.name if permitted[:owner_name].blank?
    permitted
  end
end
