# What kind of business a merchant is: restaurant, store, pharmacy, bookshop.
#
# A TABLE rather than an enum, deliberately. The supply side was broadened
# twice inside an hour — restaurant, then "restaurant or store", then "for
# example send books etc" — and an enum makes the first bookshop a migration
# while a table makes it a row.
#
# Seeded by us and not merchant-editable. Translated, because the customer app
# renders these as browse labels in all three locales.
#
# Distinct from MerchantCategory: a merchant has exactly ONE kind (what the
# business is, functionally) and MANY categories (the browse tags it carries,
# such as Kabab or Fast food).
class MerchantKind < ApplicationRecord
  has_many :merchants, dependent: :restrict_with_error

  validates :slug, presence: true, uniqueness: true
  validates :name_en, :name_fa, :name_ps, presence: true

  scope :active,  -> { where(is_active: true) }
  scope :ordered, -> { order(:position, :name_en) }

  # Falls back to English rather than nil: a blank label in the UI is worse
  # than one in the wrong language, and a missing translation is a seed bug the
  # presence validations above already prevent.
  def name_for(locale)
    case locale.to_s
    when "fa" then name_fa
    when "ps" then name_ps
    else name_en
    end.presence || name_en
  end

  # Food is prepared; a book is picked off a shelf. Used to decide whether prep
  # time is meaningful, rather than putting a meaningless 20 minutes on every
  # bookshop.
  def prepares_food?
    %w[restaurant bakery].include?(slug)
  end
end
