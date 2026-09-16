# Bearer-token authentication for the mobile app.
#
# No Devise and no devise_token_auth: the phone number is the identity and the
# only way in is an OTP, so there is no password to check and no email uid to
# authenticate against.
#
# THE ROLE IS NEVER TAKEN FROM THE CLIENT, and this file is not what enforces
# that — say where it is enforced, because a comment in the wrong place is how
# the next person builds on a guard that is not there.
#
# WHAT ENFORCES ROLE ACCESS, verified rather than assumed:
#
#   1. `ApplicationPolicy#courier?` / `#merchant_owner?` / `#admin?` /
#      `#customer?` read `user.role?(...)` — the authenticated user's own
#      `user_roles` rows — and the policy SCOPES return `.none` without the
#      role. That is the role check.
#   2. `Api::V1::BaseController` runs `verify_authorized` and
#      `verify_policy_scoped` as after_actions, so a controller that forgets
#      Pundit raises on the way out instead of answering. Every
#      `skip_authorization` in this app is on a not-found path that returns no
#      data.
#   3. The role namespaces add CAPABILITY on top of the role:
#      `Couriers::BaseController` requires an approved profile and a wallet,
#      `Merchants::BaseController` requires ownership of a merchant. Belonging
#      to something is not permission to act on it, so both layers exist.
#
# THIS FILE HELD TWO METHODS THAT LOOKED LIKE THAT ENFORCEMENT AND WERE NOT:
# `current_role` and `require_role!`, neither of which had a single caller. A
# method that reads as a security control while doing nothing is worse than no
# method, because it stops people looking for the real one — and it invites the
# next person to build authorisation on it. They were deleted rather than
# wired in, deliberately: `active_role` is which TAB a device is showing, and
# gating capability on it would break the two-phone setup that
# IDENTITY_AND_ROLES.md §6 requires — a courier whose phone is in the customer
# tab must still be able to take the job he is carrying.
module Authenticatable
  extend ActiveSupport::Concern

  included do
    attr_reader :current_user, :current_session
  end

  private

  def authenticate_user!
    return if authenticate_from_token

    render json: { error: "Unauthorized", code: "unauthorized" }, status: :unauthorized
  end

  # For guest-browsable endpoints: resolves the user when a valid token is
  # present, and never 401s a signed-out visitor.
  #
  # This is the load-bearing half of "let them browse before they log in" —
  # a first-time user on a bad connection must be able to see a merchant before
  # being asked for anything.
  def authenticate_optional!
    authenticate_from_token
    true
  end

  def authenticate_from_token
    session = UserSession.authenticate(bearer_token)
    return false if session.nil?
    # A suspended account holding a valid token must not keep working.
    return false unless session.user.account_active? && session.user.kept?

    @current_session = session
    @current_user = session.user
    session.touch_usage!
    true
  end

  def bearer_token
    header = request.headers["Authorization"].to_s
    return nil if header.blank?

    header[/\ABearer\s+(.+)\z/i, 1]
  end

  def signed_in?
    current_user.present?
  end

  # Pundit's default. Passing the user means every policy decides from the
  # authenticated identity rather than from anything the request claimed.
  def pundit_user
    current_user
  end
end
