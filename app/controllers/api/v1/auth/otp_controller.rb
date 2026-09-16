# Sends a one-time code to a phone number.
#
# Public by necessity — there is nobody to authenticate yet. Which is exactly
# why it is throttled: SMS is one of only two recurring costs in v0, so an
# unthrottled endpoint here is the owner's money, and a way to harass any
# number in Afghanistan.
class Api::V1::Auth::OtpController < ApplicationController
  # The per-PHONE limit lives in OtpVerification and is the one that protects
  # the SMS bill. This is a second line against a script rotating numbers from
  # one address — generous, because a whole Kabul neighbourhood can share an IP.
  throttle to: 60, within: 1.hour, by: :ip, only: :create

  def create
    # SWITCHED OFF, not deleted. Hamma9900 replaced the code with a password
    # and said "for now", so this refuses with a machine-readable code the app
    # can render — rather than sending an SMS, which is the one real per-unit
    # cost in this system and would be spent on a flow nothing uses.
    unless Users::SignInService.enabled?
      return render_unprocessable_entity(
        "signing in with a code is switched off — use your password",
        code: "otp_disabled"
      )
    end

    # Read rather than `require`: `params.require` treats a blank string as
    # missing and raises, which returns a bare 400 with no machine-readable
    # code — and a client rendering Pashto has nothing to translate from that.
    # A 422 naming the problem is what the app can actually act on.
    phone = params[:phone].to_s.strip
    return render_unprocessable_entity("a phone number is required", code: "phone_required") if phone.blank?

    _verification, code = OtpVerification.issue!(phone)
    deliver(phone, code)

    render_ok({ sent: true, expires_in_seconds: OtpVerification::TTL.to_i }.merge(development_hint(code)))
  rescue OtpVerification::Throttled => e
    # 429 with a NUMBER. "Too many attempts" with no indication of when to try
    # again is the dead end that loses a first-time user.
    render json: {
      error: "too many codes requested", code: "otp_throttled",
      retry_after_seconds: e.retry_after_seconds
    }, status: :too_many_requests
  end

  private

  # Composes the message and hands it to the ONE adapter class.
  #
  # There was no message at all before this — a code was logged and no text was
  # ever written, on the SMS that is the first thing anybody reads from this
  # platform. The words live in `Setting` rows because an SMS has no device to
  # translate it (see Notifications::OtpSms), and the locale comes from the
  # request so a Pashto speaker is not sent English.
  #
  # A failed send is LOGGED AND REPORTED, never swallowed: "nobody can log in"
  # must not look like "nothing happened". The response still says `sent: true`
  # because the code WAS issued and the user may still receive it on a retry —
  # and telling an attacker which numbers fail is not information worth giving.
  def deliver(phone, code)
    result = Notifications::SmsClient.deliver(
      to: phone,
      body: Notifications::OtpSms.body(code: code, locale: params[:locale])
    )

    return if result.delivered?

    Rails.logger.error("[otp] delivery failed via #{result.provider}: #{result.error}")
  end

  # Returns the code in the response OUTSIDE production only, so the mobile app
  # and the test rig can drive a real sign-in without an SMS provider.
  #
  # Guarded on `Rails.env.production?` rather than on a config flag, because a
  # flag can be set wrong in an environment file and this must not be one
  # deploy away from leaking every login code.
  def development_hint(code)
    return {} if Rails.env.production?

    { development_code: code }
  end
end
