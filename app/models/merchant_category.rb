# A global, seeded taxonomy — what the customer browses by. Kabab, Pizza,
# Burger, Grocery, Pharmacy.
#
# NOT the same thing as CatalogCategory, and this pair has been confused once
# already, so plainly:
#
#   MerchantCategory  — what a business IS. Global, seeded by us, the same rows
#                       for every merchant, translated into all three locales,
#                       and the thing customers filter and browse by. A merchant
#                       has many.
#
#   CatalogCategory   — how ONE merchant groups its own products. "Starters",
#                       "Cold drinks", "Painkillers". Typed by the merchant, in
#                       its own language and order. Not comparable across
#                       merchants and never browsed globally.
#
# Distinct from `Merchant#kind` too: `kind` is the one functional type of the
# business (restaurant / store / pharmacy); these are the many browse tags it
# carries.
class MerchantCategory < ApplicationRecord
  has_many :merchant_category_assignments, dependent: :destroy
  has_many :merchants, through: :merchant_category_assignments

  validates :slug, presence: true, uniqueness: true
  validates :name_en, :name_fa, :name_ps, presence: true

  scope :active,  -> { where(is_active: true) }
  scope :ordered, -> { order(:position, :name_en) }

  # Falls back to English rather than to nil, because a blank chip in the UI is
  # worse than a chip in the wrong language. A missing translation is a seed
  # bug, and the validation above is what stops one being created.
  def name_for(locale)
    case locale.to_s
    when "fa" then name_fa
    when "ps" then name_ps
    else name_en
    end.presence || name_en
  end

  def self.search(query)
    return all if query.blank?

    query.to_s.strip.split(/\s+/).reduce(all) do |result, word|
      term = "%#{word.downcase}%"
      result.where(
        "LOWER(name_en) LIKE :t OR LOWER(name_fa) LIKE :t OR LOWER(name_ps) LIKE :t",
        t: term
      )
    end
  end
end
