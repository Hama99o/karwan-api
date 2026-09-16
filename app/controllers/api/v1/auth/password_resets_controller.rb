# FORGOTTEN PASSWORD. Two steps: ask for a code, then set the new password.
#
# `:recoverable` has been declared on `User` since the password migration with
# NOTHING CALLING IT — the same shape as `register_device` and the arrival
# endpoint before it, and `docs/NOTES.md` records why that matters: a declared
# capability with no caller is a feature that does not exist while every gate
# stays green. Here it is worse than usual, because the sign-in path
# deliberately refuses an account with no password using the same words as a
# wrong password. Without this controller, a person who forgets their password
# is told "that email or number and password do not match" forever.
#
# A CODE, NOT A LINK: correction 16 means there is no web page for a reset link
# to open. See Users::PasswordResetService.
class Api::V1::Auth::PasswordResetsController < ApplicationController
  # Tight, and by IP rather than by identifier, because the per-phone counter
  # inside OtpVerification cannot see somebody working through a list of
  # addresses. Lower than the sign-in throttle: nobody legitimately forgets
  # their password twenty times an hour, and every attempt here costs an SMS.
  throttle to: 20, within: 1.hour, by: :ip, only: :create

  # POST — send me a code.
  def create
    result = Users::PasswordResetService.request!(
      identifier: params[:identifier].presence || params[:phone] || params[:email],
      locale: params[:locale]
    )

    # ── THE SAME ANSWER WHETHER OR NOT THE ACCOUNT EXISTS ───────────────────
    #
    # `channel` comes from the SHAPE OF WHAT WAS TYPED, not from the account,
    # so the app can say "check your messages" or "check your email" while
    # learning nothing. Saying "no account with that email" here would reopen
    # the existence oracle that `PasswordSignInService` closes — a login form
    # and a reset form are two doors to the same question.
    render_ok({ sent: true, channel: result[:channel] })
  rescue Users::PasswordResetService::Throttled => e
    render json: { error: e.message, code: "reset_throttled" }, status: :too_many_requests
  end

  # PUT — here is the code and my new password.
  def update
    _user, token, session = Users::PasswordResetService.complete!(
      identifier: params[:identifier].presence || params[:phone] || params[:email],
      code: params[:code], password: params[:password],
      device_name: params[:device_name], platform: params[:platform]
    )

    # Signed in on this device straight away. Sending somebody who just proved
    # they hold the phone back to the login screen to retype a password they
    # set four seconds ago is the kind of dead end that loses a user who is
    # already frustrated.
    render json: {
      token: token,
      user: Shared::UserSerializer.render_as_hash(_user, view: :detailed, session: session)
    }, status: :created
  rescue Users::PasswordResetService::InvalidCode => e
    render_unprocessable_entity(e.message, code: "reset_code_invalid")
  rescue Users::PasswordResetService::Invalid => e
    render_unprocessable_entity(e.message, code: "reset_invalid")
  end
end
