# Open and closed, and the merchant's own details.
#
# The open/closed toggle is its own route for the same reason as the sold-out
# toggle: it is THE most important control in the system, used in a hurry, and
# it must not be a field on a form that could fail validation for an unrelated
# reason and leave a shop marked open that isn't.
class Api::V1::Merchants::ProfilesController < Api::V1::Merchants::BaseController
  def show
    authorize current_merchant, :show?

    render_blue(Merchants::ProfileSerializer, current_merchant)
  end

  def open_now
    set_open(true)
  end

  def close_now
    set_open(false)
  end

  private

  def set_open(open)
    authorize current_merchant, :toggle_open?

    current_merchant.update!(is_open: open)
    AuditLog.record!(
      action: open ? "merchant.opened" : "merchant.closed",
      actor: current_user, actor_role: :merchant_owner, target: current_merchant,
      after: { is_open: open }
    )

    render_blue(Merchants::ProfileSerializer, current_merchant)
  end
end
