require "administrate/base_dashboard"

# When a courier was available, read-only.
#
# Same posture as the ledger beside it: a shift is a RECORD OF WHAT HAPPENED,
# and an operator editing one would falsify the only data that answers "how much
# capacity did we actually have". Shift history cannot be reconstructed — that
# is why the table exists — so nothing here is editable.
#
# The operator's questions this answers, in order of how often they are asked:
#   "utilisation looks wrong — who was actually on?"   the index, by date
#   "he says he worked all day"                        his shifts, with hours
#   "why does this one show no end?"                   `ended_by_system`
class CourierShiftDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    courier: Field::BelongsTo.with_options(class_name: "User"),
    started_at: Field::DateTime,
    ended_at: Field::DateTime,
    # SHOWN BECAUSE THE DIFFERENCE MATTERS. A shift the courier ended is an
    # observed fact; one closed by `CloseAbandonedShiftsJob` is an inference
    # drawn from their app going silent. An operator reading hours off this
    # screen is entitled to know which they are looking at.
    ended_by_system: Field::Boolean,
    created_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[courier started_at ended_at ended_by_system].freeze
  SHOW_PAGE_ATTRIBUTES = %i[courier started_at ended_at ended_by_system created_at].freeze

  # Empty on purpose. See the note above: editing a shift edits history.
  FORM_ATTRIBUTES = [].freeze

  def display_resource(shift)
    ending = shift.ended_at ? "#{shift.hours}h" : "open"
    "#{shift.courier&.display_name} — #{shift.started_at&.strftime('%d %b %H:%M')} (#{ending})"
  end
end
