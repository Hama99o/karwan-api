# A global, seeded food taxonomy — what the customer browses by.
#
# NOT the same thing as MenuCategory, which is one restaurant's own menu
# structure in its own words. A cuisine is comparable across restaurants; a
# menu category is not.
class Cuisine < ApplicationRecord
  has_many :restaurant_cuisines, dependent: :destroy
  has_many :restaurants, through: :restaurant_cuisines

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
