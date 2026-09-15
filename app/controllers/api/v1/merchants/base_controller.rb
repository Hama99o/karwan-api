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
    return if current_merchant.present?

    render json: {
      error: "no merchant is associated with this account", code: "no_merchant"
    }, status: :forbidden
  end
end
