# Bearer-token authentication for the mobile app.
#
# No Devise and no devise_token_auth: the phone number is the identity and the
# only way in is an OTP, so there is no password to check and no email uid to
# authenticate against.
#
# THE ROLE IS NEVER TAKEN FROM THE CLIENT. `current_role` is derived from the
# authenticated user's own `user_roles`, because a client-supplied role is a
# privilege escalation waiting to happen — and four roles in one app is exactly
# the shape where that gets forgotten.
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

  # Derived from what the user actually holds, never from a header or a param.
  def current_role
    current_user&.active_role
  end

  def require_role!(role)
    return if current_user&.role?(role)

    render json: { error: "Forbidden", code: "forbidden" }, status: :forbidden
  end

  # Pundit's default. Passing the user means every policy decides from the
  # authenticated identity rather than from anything the request claimed.
  def pundit_user
    current_user
  end
end
