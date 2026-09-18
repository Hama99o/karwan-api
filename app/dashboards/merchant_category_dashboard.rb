require "administrate/base_dashboard"

# WHAT A BUSINESS IS — Kabab, Pizza, Grocery, Pharmacy. The global taxonomy a
# customer browses and filters by, seeded by us and translated into all three
# locales.
#
# NOT `CatalogCategory` (how one merchant groups its own products) and NOT
# `Merchant#kind` (the one functional type). The model's own comment sets those
# three apart because the pair has been confused once already.
#
# ── Why this is routed, when MerchantKind is not ─────────────────────────
#
# `public/merchants_controller:15` filters on `category_id`, so a customer can
# already browse by these — and until 2026-09-18 **nothing could assign a
# merchant to one.** A read path whose write path does not exist: the same shape
# as the opening hours, and live rather than latent, because the filter is
# already on the customer's screen.
class MerchantCategoryDashboard < Administrate::BaseDashboard
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
  def display_resource(category)
    category.name_en.presence || category.slug
  end
end
