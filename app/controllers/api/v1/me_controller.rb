# The signed-in person: who they are, which role they are in, and where to
# send them a push.
#
# Not under a role namespace, deliberately — these are the same for all four
# roles, unlike an order, which is three different things.
class Api::V1::MeController < Api::V1::BaseController
  def show
    authorize current_user, :show?

    render_blue(Shared::UserSerializer, current_user, view: :detailed)
  end

  def update
    authorize current_user, :update?

    if current_user.update(profile_params)
      render_blue(Shared::UserSerializer, current_user, view: :detailed)
    else
      render_unprocessable_entity(current_user)
    end
  end

  # ONE ACCOUNT, SEVERAL ROLES. The switch must be obvious and fast, and the
  # app remembers the last role — which is why it is stored server-side rather
  # than only on the device: a reinstall must not drop a courier back into the
  # customer tab.
  #
  # `switch_role!` refuses a role the user does not hold, returning false
  # rather than raising, so a stale client cannot 500 this.
  def switch_role
    authorize current_user, :update?

    role = params.require(:role).to_s

    unless current_user.switch_role!(role)
      return render_unprocessable_entity(
        "you do not hold the #{role} role", code: "role_not_held"
      )
    end

    render_blue(Shared::UserSerializer, current_user.reload, view: :detailed)
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
