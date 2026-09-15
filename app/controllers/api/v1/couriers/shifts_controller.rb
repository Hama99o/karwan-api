# Going on and off shift, and reporting position.
#
# The availability toggle is the first thing on the courier's screen, so this is
# the endpoint the app hits most often after position.
class Api::V1::Couriers::ShiftsController < Api::V1::Couriers::BaseController
  def show
    authorize courier_profile, :show?

    render_ok(shift_payload)
  end

  # Going ON shift is refused when the wallet is blocked, with the reason — a
  # courier who goes online and then silently never receives an offer concludes
  # the app is broken, when in fact they need to top up.
  def update
    authorize courier_profile, :update?

    available = ActiveModel::Type::Boolean.new.cast(params[:is_available])

    if available && courier_wallet.blocked?
      return render json: {
        error: "your wallet is at its limit — top up to take work",
        code: "wallet_blocked",
        top_up_code: courier_wallet.top_up_code
      }, status: :unprocessable_content
    end

    courier_profile.update!(is_available: available)
    render_ok(shift_payload)
  end

  # Position, while a job is active. Foreground only — background location is
  # explicitly out of v0.
  #
  # Deliberately cheap: three columns, none of them indexed, so 100 writes a
  # second do not touch an index on the hot path. See
  # docs/REALTIME_AND_SCALE.md.
  def location
    authorize courier_profile, :update?

    latitude = params.require(:latitude)
    longitude = params.require(:longitude)
    courier_profile.record_location!(latitude: latitude, longitude: longitude)

    render_ok({ recorded_at: courier_profile.location_updated_at })
  end

  private

  def shift_payload
    cash = Couriers::CashPosition.new(current_user)

    {
      is_available: courier_profile.is_available,
      accepted_job_kinds: courier_profile.accepted_job_kinds,
      location_fresh: courier_profile.location_fresh?,
      wallet: {
        balance: courier_wallet.balance,
        credit_line: courier_wallet.credit_line,
        available_credit: courier_wallet.available_credit,
        blocked: courier_wallet.blocked?,
        currency: courier_wallet.currency,
        top_up_code: courier_wallet.top_up_code
      },
      # Money of ours they are holding, and what they may still collect before
      # settling. Shown rather than discovered when dispatch goes quiet.
      cash_in_hand: cash.held,
      cash_allowance_remaining: cash.remaining_allowance
    }
  end
end
