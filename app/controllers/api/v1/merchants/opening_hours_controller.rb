# The week a shop advertises.
#
# Until now these rows existed, the customer's card read them, and **the shop
# could neither see nor change them** — every correction went through an
# operator in the console. `Merchant#hours_known?` and `#next_opens_at` are
# computed from exactly this table, so the line a customer reads about when a
# shop opens was maintained by somebody who is not the shop.
class Api::V1::Merchants::OpeningHoursController < Api::V1::Merchants::BaseController
  # ── REPLACE THE WEEK, DO NOT EDIT ROWS ────────────────────────────────────
  #
  # Per-row CRUD would let a save land half-applied — Monday written, Tuesday
  # rejected — and a **half-saved week is worse than an unchanged one**, because
  # the card goes on stating hours with no indication that they are now partly
  # somebody's draft. A schedule is one thought and it is saved as one.
  #
  # So this is a full replacement inside a transaction: either the whole week
  # becomes what was sent, or nothing moves.
  def update
    authorize current_merchant, :update?

    before = week_for(current_merchant)
    rows = Array(params[:opening_hours])

    refused_row = nil
    MerchantOpeningHour.transaction do
      current_merchant.opening_hours.destroy_all
      rows.each_with_index do |row, index|
        refused_row = index
        current_merchant.opening_hours.create!(
          day_of_week: row[:day_of_week], opens_at: row[:opens_at], closes_at: row[:closes_at]
        )
      end
    end

    AuditLog.record!(
      action: "merchant.hours_updated", actor: current_user, actor_role: :merchant_owner,
      target: current_merchant, before: before, after: week_for(current_merchant.reload)
    )

    render_week
  rescue ActiveRecord::RecordInvalid => e
    # The transaction rolled the whole week back, so the shop still advertises
    # what it advertised before this call. Say WHICH row was wrong, as its index
    # in the array that was sent, and WHY, as a kind the app can put words to
    # (`same_open_and_close`, `overlaps`, `blank`, …), never the English.
    reason = e.record.errors.details.values.flatten.first&.dig(:error).to_s
    render_unprocessable_entity(e.record.errors.full_messages.to_sentence, code: "invalid_opening_hours",
                                                                          details: { row: refused_row, reason: reason })
  end

  def show
    authorize current_merchant, :show?

    render_week
  end

  private

  def render_week
    render_blue_collection(Merchants::OpeningHourSerializer, ordered_hours)
  end

  # By day, then by opening time. A day may legitimately hold MORE THAN ONE
  # window — a shop that shuts for the afternoon and reopens is ordinary here —
  # so this never collapses to one row per day, and the schema's
  # `merchant_id, day_of_week` index is deliberately not unique.
  def ordered_hours
    current_merchant.opening_hours.order(:day_of_week, :opens_at)
  end

  def week_for(merchant)
    merchant.opening_hours.order(:day_of_week, :opens_at).map do |hour|
      { day: hour.day_of_week, opens: hour.opens_at&.strftime("%H:%M"), closes: hour.closes_at&.strftime("%H:%M") }
    end
  end
end
