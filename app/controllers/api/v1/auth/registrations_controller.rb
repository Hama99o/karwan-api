# CREATES AN ACCOUNT. New, and it had to be: with OTP, signing up and signing
# in were the same action, because possessing the phone WAS the proof. With a
# password they cannot be — "sign me in" needs an account that already exists,
# and "make me an account" needs a password to be chosen. Folding them into one
# endpoint would mean a typo'd phone number silently registering a second
# account with its own wallet.
#
# Hamma9900: *"For now no authentication."* In context — he had just described
# the login — that means no VERIFICATION step. Register, set a password, you
# are in, with no code and no emailed link. Recorded in IDENTITY_AND_ROLES.md
# §1 with what it costs.
class Api::V1::Auth::RegistrationsController < ApplicationController
  # Public by necessity, and throttled by address because an account is a row
  # and a wallet — and there is no better key: every attempt is a NEW phone,
  # so a per-identifier counter would count to one.
  #
  # It was 30 an hour, which called itself generous. Behind carrier-grade NAT
  # a whole district shares one address, so the evening a campaign video goes
  # out, the 31st person on that network to register was refused. Raised with
  # the sign-in backstop on 25 Sept 2026: a registration spends no SMS (there
  # is no verification step), so the cost of a script getting 600 rows an hour
  # from one address is rows, and the cost of 30 was real people.
  throttle to: 600, within: 1.hour, by: :ip, only: :create

  def create
    user, token, session = Users::RegistrationService.new(
      phone: params[:phone], password: params[:password], email: params[:email],
      name: params[:name], locale: params[:locale],
      device_name: params[:device_name], platform: params[:platform],
      # THE DOOR THEY CAME IN BY, honoured on registration too — a rider who
      # installs the app and taps "sign in as partner" registers and lands on
      # the application form, rather than registering as a customer and having
      # to find the partner door a second time.
      requested_role: params[:role].presence
    ).call

    body = {
      token: token,
      user: Shared::UserSerializer.render_as_hash(user, view: :detailed, session: session)
    }

    # Same shape as the sign-in refusal, because the app renders one screen for
    # both: a brand-new rider holds `customer` only, so asking for `courier`
    # here is ALWAYS refused and always should be. It is not an error — it is
    # the entrance to onboarding.
    if (refusal = UserSession.role_refusal(user, params[:role].presence))
      body[:role_request] = {
        requested: params[:role], granted: false, code: refusal.to_s,
        apply_to: Api::V1::Auth::SessionsController::APPLICATION_PATHS[params[:role]]
      }
    end

    render json: body, status: :created
  rescue Users::RegistrationService::AlreadyRegistered => e
    # SAID PLAINLY, unlike the sign-in failure, and deliberately the opposite
    # trade: somebody registering has to be told to sign in instead or they
    # will try three more times and give up. Somebody signing in does not need
    # to learn whether a stranger's number is registered. The existence leak is
    # already unavoidable here — a registration form cannot both create an
    # account and hide that one exists.
    render_unprocessable_entity(e.message, code: "already_registered")
  rescue Users::RegistrationService::Invalid => e
    render_unprocessable_entity(e.message, code: "registration_invalid")
  end
end
