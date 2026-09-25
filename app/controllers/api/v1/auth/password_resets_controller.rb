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
  # ── PER IDENTIFIER, WITH THE ADDRESS AS A BACKSTOP (25 Sept 2026) ────────
  #
  # It was 20 an hour per IP. Behind carrier-grade NAT that is a district, so
  # the 21st person on one network in an hour to forget a password was
  # refused, at the door people use when they are already stuck. Hamma9901's
  # decision: the same shape as sign-in. The SMS bill is incurred PER NUMBER,
  # so a per-identifier limit caps exactly what costs money.
  #
  # The identifier limits EQUAL OtpVerification's per-phone limits, read from
  # the same Settings, and are checked first. So for any identifier, real or
  # not, the refusal comes from here in identical words. OtpVerification's own
  # `reset_throttled`, which implied an account existed, is no longer reached
  # by one identifier. Counted on every request, whether or not an account
  # exists, because every request for a real one sends something.
  throttle to: 300, within: 1.hour, by: :ip, only: :create

  before_action :refuse_a_throttled_identifier, only: :create

  # POST — send me a code.
  def create
    count_this_reset_request
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

  private

  def reset_windows
    raw = params[:identifier].presence || params[:phone] || params[:email]
    typed = Users::Identifier.resolve(raw)&.value || raw.to_s.strip.downcase
    key = "reset-requests:#{OpenSSL::Digest::SHA256.hexdigest(typed)}"
    [
      [ rate_limit_window("#{key}:burst", Setting.fetch("otp_send_window_minutes").minutes),
        Setting.fetch("otp_max_sends_per_window") ],
      [ rate_limit_window("#{key}:day", 1.day), Setting.fetch("otp_max_sends_per_day") ]
    ]
  end

  def refuse_a_throttled_identifier
    reset_windows.each do |window, limit|
      count = rate_limit_safely { window.count }
      return render_too_many_requests(window.retry_after_seconds) if count && count >= limit
    end
  end

  def count_this_reset_request
    reset_windows.each { |window, _| rate_limit_safely { window.hit! } }
  end
end
