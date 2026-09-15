require "administrate/base_dashboard"

# The Config screen from PRODUCT.md.
#
# Commission %, delivery fee, courier fee, cash-in-hand limit, default credit
# line, ETA average speed, the ride fare terms. **Editable with no deploy is
# the whole point** — Hamma9900 tunes prices by typing, and the pricing
# services already read these rows.
class SettingDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    key: Field::String,
    value: Field::String,
    value_type: Field::Select.with_options(collection: ->(_f) { Setting.value_types.keys }),
    currency: Field::String,
    description: Field::Text,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[key value currency description].freeze
  SHOW_PAGE_ATTRIBUTES = %i[key value value_type currency description updated_at].freeze
  # Only the VALUE is editable. The key, type and description are ours: a typo
  # in a key silently creates a row nothing reads, and `Setting.fetch` raises on
  # an unknown key precisely so that cannot happen quietly.
  FORM_ATTRIBUTES = %i[value].freeze

  def display_resource(setting)
    setting.key
  end
end
