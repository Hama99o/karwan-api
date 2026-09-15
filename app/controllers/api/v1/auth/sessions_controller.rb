# Exchanges a phone number and a code for a bearer token.
#
# Sign-up and sign-in are the same endpoint: if the number is new the account is
# created, if it is known they are signed in. Nobody should have to choose
# between "register" and "log in".
class Api::V1::Auth::SessionsController < ApplicationController
  def create
    user, token = Users::SignInService.new(
      phone: params.require(:phone), code: params.require(:code),
      name: params[:name], locale: params[:locale],
      device_name: params[:device_name], platform: params[:platform]
    ).call

    render json: {
      token: token,
      user: Shared::UserSerializer.render_as_hash(user, view: :detailed)
    }, status: :created
  rescue Users::SignInService::NoCodeIssued => e
    render_unprocessable_entity(e.message, code: "otp_not_issued")
  rescue Users::SignInService::CodeNoLongerValid => e
    # Distinct from `otp_invalid` on purpose: the app should offer "send a new
    # code" here rather than "check the digits and try again".
    render_unprocessable_entity(e.message, code: "otp_expired")
  rescue Users::SignInService::InvalidCode => e
    render_unprocessable_entity(e.message, code: "otp_invalid")
  rescue Users::SignInService::Error => e
    render json: { error: e.message, code: "account_unavailable" }, status: :forbidden
  end

  # Signing out revokes THIS session only. A courier with a phone and a tablet
  # signing out of one must stay signed in on the other.
  def destroy
    return render json: { error: "Unauthorized", code: "unauthorized" }, status: :unauthorized unless authenticate_from_token

    current_session.revoke!
    head :no_content
  end
end
