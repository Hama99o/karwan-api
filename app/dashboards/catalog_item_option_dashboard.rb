require "administrate/base_dashboard"

# "Size", "Extras", "Spice" — a choice a customer makes on one dish.
#
# ── WHY THIS IS ROUTED ────────────────────────────────────────────────────
#
# CLAUDE.md's data model puts these in v0 and says so in the sharpest terms
# available: **"This is bigger than it looks; keep it simple but do not skip
# it."** It was not skipped — the model, the values, the cart resolver, the
# order-time snapshot and the customer's payload were all built.
#
# **Nothing could create one.** The merchant API only READS them
# (`includes(catalog_items: { options: :values })`), there was no console door,
# and the two that exist in any database came from a seed. So a restaurant
# selling "Chicken Kabab — large, +100" could not say so, while every layer
# downstream was ready to carry it.
#
# The same shape as the opening hours and the menu itself: a read path whose
# write path did not exist, found by `bin/console_doors` pointed at its own
# leftovers.
class CatalogItemOptionDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    catalog_item: Field::BelongsTo,
    name: Field::String,
    # `single` is a radio, `multiple` a set of checkboxes. The app renders from
    # this rather than guessing from min/max.
    selection_type: Field::Select.with_options(collection: ->(_f) { CatalogItemOption.selection_types.keys }),
    required: Field::Boolean,
    min_selections: Field::Number,
    max_selections: Field::Number,
    position: Field::Number,
    values: Field::HasMany,
    created_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[catalog_item name selection_type required].freeze
  SHOW_PAGE_ATTRIBUTES = %i[
    catalog_item name selection_type required min_selections max_selections
    position values created_at
  ].freeze
  FORM_ATTRIBUTES = %i[
    catalog_item name selection_type required min_selections max_selections position
  ].freeze

  def display_resource(option)
    "#{option.catalog_item&.name} — #{option.name}"
  end
end
