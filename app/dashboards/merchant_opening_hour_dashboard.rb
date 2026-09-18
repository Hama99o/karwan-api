require "administrate/base_dashboard"

# WHEN A SHOP IS OPEN — and until 2026-09-18 there was no way to say.
#
# `MerchantOpeningHour` had no dashboard, no route, and no place on the
# merchant's show page, so an operator could not see a shop's hours OR set
# them. 201 of 205 merchants had none; the four that did were seeded. The
# customer-facing `opening_hours` field has been on the wire the whole time,
# returning `[]` for almost every shop.
#
# PRODUCT.md is explicit that **admin onboards restaurants** — the shop does not
# edit its own identity in v0 — which makes the console the only place hours can
# come from. So the write path missing here is why the read path means nothing.
#
# ── Advisory, and the console should not imply otherwise ─────────────────
# `Merchant#is_open` is the manual toggle that decides whether orders are
# accepted. These rows exist so a closed shop can show when it opens again. An
# operator setting hours is not opening the shop.
class MerchantOpeningHourDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    merchant: Field::BelongsTo,
    # 0 = Sunday, matching Ruby's `Time#wday`. NOT the Afghan week, which starts
    # Saturday — the model stores wday and display order is the client's job.
    day_of_week: Field::Number,
    opens_at: Field::Time,
    closes_at: Field::Time,
    created_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[merchant day_of_week opens_at closes_at].freeze
  SHOW_PAGE_ATTRIBUTES = %i[merchant day_of_week opens_at closes_at created_at].freeze
  FORM_ATTRIBUTES = %i[merchant day_of_week opens_at closes_at].freeze

  COLLECTION_FILTERS = {}.freeze

  # Sunday..Saturday rather than 0..6. An operator reading a table of integers
  # has to remember which end the week starts, and the model's own comment says
  # this numbering is not the Afghan one.
  DAY_NAMES = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday].freeze

  def display_resource(hours)
    day = DAY_NAMES[hours.day_of_week.to_i] || "day #{hours.day_of_week}"
    "#{hours.merchant&.name} — #{day}"
  end
end
