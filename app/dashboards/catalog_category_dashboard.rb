require "administrate/base_dashboard"

# ONE MERCHANT'S OWN MENU STRUCTURE — "Kababs", "Drinks". Not browsable across
# merchants, which is why the cross-merchant taxonomy is `MerchantCategory` and
# these two are different things.
#
# Not routed: a merchant owns their menu and edits it in the app.
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
  FORM_ATTRIBUTES = [].freeze

  def display_resource(category)
    category.name
  end
end
