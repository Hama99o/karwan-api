# ── THE RIDER SCREEN NOTHING SERVED ───────────────────────────────────────
#
# `PRODUCT.md`: *"**Today** — deliveries, earnings, cash currently in hand."*
# Every other Rider screen has an endpoint; this had none, so a courier ending
# a shift could not answer what he had earned without adding up wallet entries.
#
# SINGULAR, for the same reason as the merchant's: there is one today. A date
# parameter here would be a second earnings history beside the wallet entries,
# which is how one question gets two answers.
class Api::V1::Couriers::TodayController < Api::V1::Couriers::BaseController
  def show
    authorize courier_profile, :show?

    render_ok(Couriers::TodaysWork.new(current_user).call)
  end
end
