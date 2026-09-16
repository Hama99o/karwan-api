# Exchanges a phone number and a code for a bearer token.
#
# Sign-up and sign-in are the same endpoint: if the number is new the account is
# created, if it is known they are signed in. Nobody should have to choose
# between "register" and "log in".
class Api::V1::Auth::SessionsController < ApplicationController
  # WHERE A REFUSED PARTNER APPLIES. A rider or a driver applies and waits for
  # approval; a restaurant leaves its details and gets a phone call
  # (IDENTITY_AND_ROLES.md §5). Both are "we will get back to you" and neither
  # is an error state, which is why the refusal carries a path rather than only
  # a message.
  APPLICATION_PATHS = {
    "courier" => "/api/v1/courier/registration",
    "merchant_owner" => "/api/v1/merchant_application"
  }.freeze

  # Code guesses are already capped per code by OtpVerification::MAX_ATTEMPTS.
  # This bounds a script working through many phone numbers from one address.
  throttle to: 120, within: 1.hour, by: :ip, only: :create

  # THE ROLE IS CHOSEN AT THE DOOR, and `role` is optional because customer is
  # the default and is never asked — asking "what are you?" of somebody who
  # wants a kebab is a question that loses the user. "Sign in as partner" is a
  # quieter second action that sends one.
  def create
    requested_role = params[:role].presence

    user, token, session = Users::SignInService.new(
      phone: params.require(:phone), code: params.require(:code),
      name: params[:name], locale: params[:locale],
      device_name: params[:device_name], platform: params[:platform],
      requested_role: requested_role
    ).call

    body = {
      token: token,
      user: Shared::UserSerializer.render_as_hash(user, view: :detailed, session: session)
    }

    # SIGNING IN STILL SUCCEEDS when the role is refused, and the refusal rides
    # along beside the token. Failing the whole request would consume the code
    # and hand back nothing, costing a second SMS — and it would strand exactly
    # the person we most want to reach: someone signing in as a courier who has
    # not applied yet. `role_not_held` is the front door to onboarding, so the
    # app can offer the application path instead of showing an error.
    if (refusal = UserSession.role_refusal(user, requested_role))
      body[:role_request] = {
        requested: requested_role, granted: false, code: refusal.to_s,
        # THE PATH TO THE FORM, not a screen name: which of our own endpoints
        # this person should apply to. Naming a client route here would couple
        # the API to the app's navigation, which correction 18 forbids —
        # naming an API resource does not.
        #
        # nil for `not_a_mobile_role`, because there is nothing to apply for,
        # and the app must say something different about that.
        apply_to: APPLICATION_PATHS[requested_role]
      }
    end

    render json: body, status: :created
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
