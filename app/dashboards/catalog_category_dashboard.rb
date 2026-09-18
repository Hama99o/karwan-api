require "administrate/base_dashboard"

# ONE MERCHANT'S OWN MENU STRUCTURE — "Kababs", "Drinks". Not browsable across
# merchants, which is why the cross-merchant taxonomy is `MerchantCategory` and
# these two are different things.
#
# ROUTED SINCE 2026-09-18, and the comment that used to sit here — "a merchant
# owns their menu and edits it in the app" — was a stale premise believed for
# weeks. PRODUCT.md:22 puts the console in phase 1 precisely because "you cannot
# test an order without a restaurant and a menu"; :66 says admin onboards
# restaurants, and a restaurant being onboarded does not have the app yet. The
# merchant's own screen at :78 is for MID-RUSH work — sold-out in one tap, a
# price fix — which presupposes a menu that already exists.
#
# Before this, a menu could only arrive from a seed, so the first real
# restaurant could not be onboarded at all.
class CatalogCategoryDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    merchant: Field::BelongsTo,
    name: Field::String,
    position: Field::Number,
    catalog_items: Field::HasMany,
    deleted_at: Field::DateTime,
    created_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[name position].freeze
  SHOW_PAGE_ATTRIBUTES = %i[merchant name position catalog_items deleted_at created_at].freeze
  # `deleted_at` is deliberately absent: soft delete is an ACTION (discard),
  # not a date an operator types. Editing it by hand would bypass
  # `discard_dependents!` and leave a category hidden with its items visible.
  FORM_ATTRIBUTES = %i[merchant name position].freeze

  def display_resource(category)
    category.name
  end
end
