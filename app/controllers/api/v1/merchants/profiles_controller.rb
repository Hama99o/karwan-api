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

  # ── WHAT A SHOP MAY CORRECT ABOUT ITSELF ──────────────────────────────────
  #
  # Until now `GET profile` existed and nothing wrote it, so a shop could not
  # change its own phone number without an operator doing it in the console.
  # `docs/NOTES.md` recorded that as open.
  #
  # **`prep_time_minutes` is the one that earns this endpoint.** It feeds
  # `Orders::ArrivalWindow`, so it is the number behind the range the customer
  # is shown. The kitchen is the only party that knows it is slammed tonight,
  # and today telling anyone means ringing an operator — so the honest answer
  # is the one nobody can give in a rush.
  #
  # ── WHAT IS DELIBERATELY NOT HERE ─────────────────────────────────────────
  #
  # **The map pin.** `latitude`/`longitude` decide distance, distance decides
  # the delivery fee, and `MAP_AND_ROUTING.md` requires a fare to be
  # explainable afterwards. A shop nudging its own pin is a MONEY change
  # wearing a profile edit's clothes, and it would move every future fare with
  # nothing on the order saying why. Left with the operator; the question of
  # whether audited self-service would do is in `docs/NOTES.md`.
  #
  # **`name`, `commission_rate`, `status`, the verification fields.** Identity
  # and terms. Correction: admin onboards restaurants, and their app is a
  # workbench rather than a shop.
  #
  # **Opening hours.** A collection on another table, and the card's hours line
  # reads it — its own endpoint, its own pass.
  def update
    authorize current_merchant, :update?

    before = current_merchant.slice(*EDITABLE)
    current_merchant.update!(profile_params)

    # Door 5 is an audit row for every intervention, and this is a shop
    # changing what customers are promised. `before` and `after` both, because
    # "prep time is 40" answers nothing without "it was 15".
    AuditLog.record!(
      action: "merchant.profile_updated", actor: current_user, actor_role: :merchant_owner,
      target: current_merchant, before: before, after: current_merchant.slice(*EDITABLE)
    )

    render_blue(Merchants::ProfileSerializer, current_merchant)
  end

  def open_now
    set_open(true)
  end

  def close_now
    set_open(false)
  end

  private

  EDITABLE = %w[phone description prep_time_minutes landmark_note].freeze

  def profile_params
    params.require(:merchant).permit(*EDITABLE)
  end

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
