# The signed-in person: who they are, which role they are in, and where to
# send them a push.
#
# Not under a role namespace, deliberately — these are the same for all four
# roles, unlike an order, which is three different things.
class Api::V1::MeController < Api::V1::BaseController
  # The app re-registers on every launch, so this must be loose enough never to
  # bite a real relaunch loop while still bounding a script.
  throttle to: 200, within: 1.hour, by: :user, only: :register_device

  def show
    authorize current_user, :show?

    render_blue(Shared::UserSerializer, current_user, view: :detailed,
                options: { session: current_session })
  end

  def update
    authorize current_user, :update?

    if current_user.update(profile_params)
      render_blue(Shared::UserSerializer, current_user, view: :detailed,
                options: { session: current_session })
    else
      render_unprocessable_entity(current_user)
    end
  end

  # ONE ACCOUNT, SEVERAL ROLES, AND THE SWITCH IS PER DEVICE.
  #
  # It switches THIS session, so a merchant flipping his pocket phone to the
  # customer tab does not flip the tablet on the counter. It also writes the
  # choice through to the user as a preference, which is what makes the app
  # remember: a reinstall is a new session, and a courier must not land back in
  # the customer tab after one.
  #
  # `switch_role!` returns false for exactly one reason — the user does not
  # hold that role — so a stale client cannot 500 this.
  def switch_role
    authorize current_user, :update?

    role = params.require(:role).to_s

    unless current_session.switch_role!(role)
      return render_unprocessable_entity(
        "you do not hold the #{role} role", code: "role_not_held"
      )
    end

    render_blue(Shared::UserSerializer, current_user.reload, view: :detailed,
                options: { session: current_session })
  end

  # WHERE TO SEND A PUSH.
  #
  # Without this the merchant alert has nothing to deliver to — the model and
  # the sender existed before any way for a phone to report its token, which
  # made the whole alert chain untestable end to end.
  #
  # Idempotent, because the app re-registers on every launch: a
  # unique-constraint error here would break the launch rather than the push.
  # Re-registering also MOVES the token to whoever is signed in now, since a
  # merchant tablet gets handed between staff and the alert must not keep going
  # to somebody who went home.
  def register_device
    authorize current_user, :update?

    token = params.require(:token).to_s
    platform = params[:platform].presence || "android"

    unless DeviceToken.platforms.key?(platform)
      return render_unprocessable_entity(
        "platform must be one of: #{DeviceToken.platforms.keys.join(', ')}", code: "bad_platform"
      )
    end

    device = DeviceToken.register!(user: current_user, token: token, platform: platform)

    render_ok({ registered: true, platform: device.platform })
  end

  # On sign-out from a shared phone, so the next person does not receive this
  # person's orders. AFGHAN_UX: phones are shared.
  def unregister_device
    authorize current_user, :update?

    DeviceToken.where(user: current_user, token: params.require(:token).to_s)
               .find_each(&:deactivate!)

    head :no_content
  end
end
