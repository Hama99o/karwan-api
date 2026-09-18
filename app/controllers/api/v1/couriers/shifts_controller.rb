# Going on and off shift, and reporting position.
#
# The availability toggle is the first thing on the courier's screen, so this is
# the endpoint the app hits most often after position.
class Api::V1::Couriers::ShiftsController < Api::V1::Couriers::BaseController
  # ── THE WRITE SIDE OF LIVE TRACKING, WHICH WAS THE UNCAPPED ONE ────────────
  #
  # The customer POLLING this position is throttled at 1,200/hour
  # (`Customers::OrdersController`, `:track`). The courier WRITING it was not
  # throttled at all — so the cheap read was capped and the DB write was open.
  # Found walking phase 6, by listing the throttles rather than by reading here,
  # where nothing looks wrong.
  #
  # The number is deliberately the SAME as the poll it pairs with, rather than a
  # fresh guess: one report per position, one poll per position. At a 10-second
  # cadence a 40-minute delivery reports 240 times, so 1,200/hour is far above
  # any real use and caps a runaway at one every three seconds.
  #
  # It exists for the retry loop, not for abuse. A bad connection is the normal
  # condition here, and a client that retries a failed position report in a tight
  # loop is the likeliest way this endpoint ever gets hammered — on a VPS that is
  # Hamma9900's own money (correction 6).
  #
  # `by: :user` and not `:ip`: couriers share carrier NAT, so an IP limit would
  # throttle a neighbourhood to punish one handset — the same reasoning
  # `RoutesController` gives.
  throttle to: 1_200, within: 1.hour, by: :user, only: :location

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
