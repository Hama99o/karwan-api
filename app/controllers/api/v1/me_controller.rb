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

  # ── CLOSING THE ACCOUNT ─────────────────────────────────────────────────
  #
  # Required by both app stores, which is why it exists at all — and the most
  # dangerous endpoint in this API, because the person pressing it may be
  # holding our cash. `Users::AccountDeletion` names which check refused it so
  # the app can say what to fix; a bare 422 would read as "the app is broken"
  # to a courier who simply needs to settle first.
  #
  # `discard!`, never destroy — one-way door 6. Orders carry their own
  # `customer_phone` snapshot, so the books survive the row.
  #
  # OPEN, and it belongs to Hamma9900 rather than to this code: `phone` is
  # unique and NOT scoped to `kept`, so a closed account keeps its number and
  # that person can never register again with it. Releasing the number would
  # make deletion complete but would also defeat the console's restore, which
  # is the only thing standing between a mistaken tap and a courier's ledger.
  # Left reversible on purpose; recorded in docs/NOTES.md.
  def destroy
    authorize current_user, :update?

    deletion = Users::AccountDeletion.new(current_user)

    unless deletion.allowed?
      return render json: { error: deletion.explanation, code: deletion.reason.to_s },
                    status: :unprocessable_content
    end

    deletion.call
    # 200 with a body rather than 204: the app shows a "your account is closed"
    # screen, and a no-content response gives it nothing to key that on.
    render_ok({ deleted: true })
  end

  # ── REMOVING MUST BE AS EASY AS SETTING ─────────────────────────────────
  #
  # Hamma9900's requirement, and it is a product one rather than a nicety:
  # people change their mind about a photograph of their own face, and a user
  # who cannot take it down has to ring support — on a platform whose support
  # is a human with a phone, in Dari, in Kabul. So removal is its own verb on
  # its own route, not a PATCH with a magic empty string that a client has to
  # know to send.
  #
  # Idempotent: removing an avatar that is not there is a 200, not a 404.
  # A client retrying after a dropped connection must not get an error for
  # having succeeded the first time.
  def destroy_avatar
    authorize current_user, :update?

    current_user.avatar.purge_later if current_user.avatar.attached?

    render_blue(Shared::UserSerializer, current_user.reload, view: :detailed,
                options: { session: current_session })
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

  private

  # ── WHAT A PERSON MAY CHANGE ABOUT THEMSELVES ─────────────────────────────
  #
  # `name` and `locale`, and nothing else.
  #
  # **This method did not exist.** `update` above has called it since it was
  # written, so `PATCH /api/v1/me` answered 500 with
  # `undefined local variable or method 'profile_params'` for its whole life —
  # a declared endpoint that had never once worked, with no request spec to say
  # so. Found while building the Profile screen, which is its first caller.
  #
  # ── THE TWO FIELDS THAT ARE NOT HERE, AND WHY ────────────────────────────
  #
  # **The phone.** It is the identity — NOT NULL, unique, normalised, and the
  # number a courier rings from outside the gate. Changing it is an identity
  # change and would need a verification step this platform deliberately does
  # not have (`docs/IDENTITY_AND_ROLES.md` §1, Hamma9900: *"For now no
  # authentication."*).
  #
  # **The email, and this one is less obvious.** It is the additional
  # identifier AND a password-reset channel. With no verification, letting a
  # session add an address would let somebody holding a BORROWED PHONE add
  # their own and then reset the password — and `AFGHAN_UX.md` §7 is explicit
  # that shared handsets are normal here rather than hypothetical. So adding or
  # changing an email is a support action until the address can be proven.
  #
  # `locale` is included on purpose: `AFGHAN_UX.md` §8 wants the language
  # remembered per PERSON rather than per device, precisely because phones are
  # shared. An invalid value is refused by the model's own validation rather
  # than filtered here, so the client gets told which field was wrong.
  def profile_params
    params.permit(:name, :locale, :preferred_theme, :avatar)
  end
end
