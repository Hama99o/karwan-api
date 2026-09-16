require "administrate/base_dashboard"

# What KIND of place this is — restaurant, bakery, pharmacy. A taxonomy row
# rather than a string on the merchant, because "delivery needs a restaurant or
# a store or a place" and the list grows.
#
# Not routed yet: the three localised names are content, and content Hamma9900
# edits is a `Setting`-shaped problem that has not been solved for taxonomies.
class MerchantKindDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    slug: Field::String,
    name_ps: Field::String,
    name_fa: Field::String,
    name_en: Field::String,
    position: Field::Number,
    is_active: Field::Boolean,
    merchants: Field::HasMany,
    created_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[slug name_en position is_active].freeze
  SHOW_PAGE_ATTRIBUTES = %i[slug name_ps name_fa name_en position is_active merchants created_at].freeze
  FORM_ATTRIBUTES = %i[slug name_ps name_fa name_en position is_active].freeze

  # English on purpose: correction 16 — the console is a laptop on a desk and
  # may be English-only if that is faster for Hamma9900 to operate.
  def display_resource(kind)
    kind.name_en.presence || kind.slug
  end
end
