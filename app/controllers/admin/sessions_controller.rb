# Admin login — deliberately standalone.
#
# Inherits ActionController::Base, NOT the API ApplicationController (which
# cannot render HTML) and NOT Admin::ApplicationController (whose
# authenticate_admin_user! would lock you out of the login page itself).
#
# Authentication is explicit so the highest-privilege account in the system
# keeps Devise's protections:
#   * valid_for_authentication? runs the password check inside Lockable, so
#     failed attempts increment and the account locks after the maximum.
#   * active_for_authentication? refuses login while locked.
#   * sign_in triggers trackable, recording count, timestamps and IP.
module Admin
  class SessionsController < ActionController::Base
    protect_from_forgery with: :exception
    layout "admin/auth"

    def new
      @admin_user = AdminUser.new
    end

    def create
      admin_user = AdminUser.find_for_database_authentication(email: login_params[:email])
      verified = admin_user&.valid_for_authentication? { admin_user.valid_password?(login_params[:password]) }

      if verified && admin_user.active_for_authentication?
        sign_in(:admin_user, admin_user)
        AuditLog.record!(action: "admin.signed_in", admin_user: admin_user,
                         actor_role: :admin, ip: request.remote_ip)
        redirect_to admin_root_path, notice: "Signed in."
      elsif admin_user && !admin_user.active_for_authentication?
        deny("This account is locked. Try again later.")
      else
        # The same message either way, so nobody can enumerate which addresses
        # are admin accounts.
        deny("Invalid email or password.")
      end
    end

    def destroy
      sign_out(:admin_user)
      redirect_to new_admin_user_session_path, notice: "Signed out."
    end

    private

    def deny(message)
      flash.now[:alert] = message
      @admin_user = AdminUser.new(email: login_params[:email])
      render :new, status: :unprocessable_content
    end

    def login_params
      params.fetch(:admin_user, {}).permit(:email, :password)
    end
  end
end
