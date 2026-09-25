# Everything a courier does happens as themselves, against their own profile.
class Api::V1::Couriers::BaseController < Api::V1::BaseController
  before_action :require_courier!

  private

  def courier_profile
    @courier_profile ||= current_user.courier_profile
  end

  def courier_wallet
    @courier_wallet ||= current_user.courier_wallet
  end

  # An approved profile AND a wallet. A courier without a wallet cannot be
  # charged commission, so they must not be able to take work — and the error
  # says which is missing, because "forbidden" sends an operator hunting.
  #
  # `no_profile` is Eligibility's word for the same fact, so the app says one
  # sentence for both. Until 25 Sept 2026 this door said `no_courier_profile`
  # (see ErrorCodes).
  def require_courier!
    return render_courier_error("no courier profile on this account", "no_profile") if courier_profile.nil?
    return render_courier_error("this courier account is not approved", "not_approved") unless courier_profile.verification_approved?
    return render_courier_error("no wallet on this courier account", "no_wallet") if courier_wallet.nil?

    nil
  end

  def render_courier_error(message, code)
    render json: { error: message, code: code }, status: :forbidden
  end

  # The courier scope for whichever demand type is being asked about. Each job
  # class owns its own policy, so a third demand type brings its own scope
  # rather than borrowing Order's.
  def courier_jobs(klass)
    policy_scope(klass, policy_scope_class: "#{klass.name}Policy::CourierScope".constantize)
  end
end
