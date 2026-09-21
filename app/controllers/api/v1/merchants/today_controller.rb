# ── THE FIFTH RESTAURANT SCREEN ───────────────────────────────────────────
#
# `PRODUCT.md` names five screens for this role and this is the one nothing
# served: *"**Today** — orders, items sold, cash received from riders, our
# commission. No charts."*
#
# SINGULAR, because there is one today. A `resources` here would invite a date
# parameter and a history screen, which is the weekly statement's job — and two
# ways to ask the same question is how two answers appear.
class Api::V1::Merchants::TodayController < Api::V1::Merchants::BaseController
  def show
    authorize current_merchant, :show?

    render_ok(Merchants::TodaysTrade.new(current_merchant).call)
  end
end
