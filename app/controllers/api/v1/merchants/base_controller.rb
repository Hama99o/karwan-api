# Everything a merchant does happens against THEIR merchant.
#
# Resolved once, here, from the authenticated user's ownership — never from a
# `merchant_id` in the request. A merchant_id parameter is how one restaurant
# reads another's orders, and it is the exact shape of edu-safi's five
# unconsulted-scope endpoints.
class Api::V1::Merchants::BaseController < Api::V1::BaseController
  before_action :require_merchant!

  private

  def current_merchant
    @current_merchant ||= ::Merchant.kept.find_by(owner_id: current_user.id)
  end

  def require_merchant!
    # A LEAD IS NOT A MERCHANT ACCOUNT. Assigning an owner is what grants the
    # role, and Hamma9900 may well assign one while calling a shop that is
    # still a `lead` — that must not hand over the order board of a shop whose
    # terms nobody has agreed. `pending` deliberately DOES pass: a merchant
    # being onboarded builds their menu before they go live.
    if current_merchant&.status_lead?
      return render json: {
        error: "this shop is still an application — we will call you", code: "merchant_is_a_lead"
      }, status: :forbidden
    end

    return if current_merchant.present?

    render json: {
      error: "no merchant is associated with this account", code: "no_merchant"
    }, status: :forbidden
  end
end
