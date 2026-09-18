require "administrate/base_dashboard"

# One thing on one menu. `is_available` is the sold-out toggle, which is the
# control a merchant reaches for most often on a busy evening.
#
# ROUTED SINCE 2026-09-18 — see CatalogCategoryDashboard for why the "the
# merchant owns their menu" premise was stale. This page also exists so support
# can SEE what a customer ordered from, with the currency visible next to the
# price — never sum across currencies.
class CatalogItemDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    merchant: Field::BelongsTo,
    catalog_category: Field::BelongsTo,
    name: Field::String,
    description: Field::Text,
    price: Field::Number.with_options(decimals: 2),
    # PRODUCT.md:78 names the photo as part of menu management, and it was not
    # on this dashboard at all — so an operator could neither see nor set it.
    # AFGHAN_UX makes it the label for a customer who cannot read fluently.
    photo: AttachmentField,
    currency: Field::String,
    is_available: Field::Boolean,
    # The choices on this dish, reachable from the dish rather than only from a
    # list — an operator building a menu is on the item's page already.
    options: Field::HasMany,
    # Decides which vehicles may be offered the order (`VehicleTypes::CARRIES`).
    # A restaurant never touches it — food is always `small` — but a furniture
    # shop sets `bulky` on beds once, at onboarding, which is here.
    size_class: Field::Select.with_options(collection: SizeClasses::ALL.keys.map(&:to_s)),
    prep_time_minutes: Field::Number,
    position: Field::Number,
    deleted_at: Field::DateTime,
    created_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[name price currency is_available].freeze
  SHOW_PAGE_ATTRIBUTES = %i[
    merchant catalog_category name description price currency photo options is_available
    prep_time_minutes position deleted_at created_at
  ].freeze
  # WHAT IS DELIBERATELY NOT HERE, because the wallet taught the lesson: what an
  # operator must fix is editable, and what must not be bypassed is not.
  #
  #   `currency`   — defaults to AFN in the schema. An operator typing a
  #                  currency is exactly the mixed-currency total CLAUDE.md
  #                  records as already shipped once in another app.
  #   `deleted_at` — soft delete is an action, not a date somebody types.
  FORM_ATTRIBUTES = %i[
    merchant catalog_category name description price photo is_available
    prep_time_minutes position size_class
  ].freeze

  def display_resource(item)
    item.name
  end
end
