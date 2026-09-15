class Restaurant < ApplicationRecord
  include SoftDeletable
  include TrigramSearchable

  enum :status, { pending: 0, active: 1, suspended: 2, rejected: 3 }, prefix: true

  # Nullable: admin onboards restaurants, so one exists before its owner has an
  # account. Restaurants are not self-serve in v0.
  belongs_to :owner, class_name: User.name, optional: true, inverse_of: :owned_restaurants
  belongs_to :verified_by, class_name: User.name, optional: true

  has_many :opening_hours, class_name: RestaurantOpeningHour.name, dependent: :destroy,
                           inverse_of: :restaurant
  has_many :menu_categories, -> { order(:position) }, dependent: :destroy, inverse_of: :restaurant
  has_many :menu_items, dependent: :destroy
  has_many :restaurant_cuisines, dependent: :destroy
  has_many :cuisines, through: :restaurant_cuisines
  has_many :orders, dependent: :restrict_with_error

  has_one_attached :logo
  has_one_attached :storefront_photo
  has_one_attached :license_photo

  validates :name, presence: true
  validates :phone, presence: true
  validates :prep_time_minutes, numericality: { greater_than: 0 }
  validates :commission_rate, numericality: { greater_than_or_equal_to: 0, less_than: 1 }

  scope :listed,       -> { kept.status_active }
  scope :orderable,    -> { listed.where(is_open: true) }
  scope :alphabetical, -> { order(:name) }
  scope :by_cuisine,   ->(cuisine_id) { joins(:restaurant_cuisines).where(restaurant_cuisines: { cuisine_id: cuisine_id }) }

  # People search for a DISH, not a restaurant — "mantu" is food, not a shop.
  # So a restaurant matches on its own name, on the name of any available dish
  # it sells, or on one of its cuisines.
  #
  # Multi-word: each word narrows the result, and each word may match any of the
  # three. This is the house rule from hatiwal-api's backend prompt, and it is
  # what makes "chicken kabab" behave the way a person expects.
  #
  # EXISTS subqueries rather than joins, deliberately: a join against menu_items
  # returns one row per matching dish, so a restaurant with four matching dishes
  # appears four times, and the DISTINCT you then reach for breaks ordering by
  # similarity later. EXISTS asks the only question being asked — is there one?
  def self.search(query)
    return all if query.blank?

    query.to_s.strip.split(/\s+/).reduce(all) do |result, word|
      term = "%#{word.downcase}%"
      result.where(
        "LOWER(restaurants.name) LIKE :t
         OR EXISTS (
              SELECT 1 FROM menu_items mi
              WHERE mi.restaurant_id = restaurants.id
                AND mi.deleted_at IS NULL
                AND mi.is_available = TRUE
                AND LOWER(mi.name) LIKE :t
            )
         OR EXISTS (
              SELECT 1 FROM restaurant_cuisines rc
              JOIN cuisines c ON c.id = rc.cuisine_id
              WHERE rc.restaurant_id = restaurants.id
                AND (LOWER(c.name_en) LIKE :t OR LOWER(c.name_fa) LIKE :t OR LOWER(c.name_ps) LIKE :t)
            )",
        t: term
      )
    end
  end

  # Fallback for when `search` returns nothing because of a typo or a different
  # transliteration. Ranked by similarity, so the closest spelling comes first.
  def self.fuzzy(query)
    fuzzy_on(:name, query)
  end

  # `is_open` is a MANUAL toggle and is the authority. Opening hours are
  # advisory — they tell a customer when to come back, they do not open the
  # restaurant. A restaurant that forgot to close must be closeable by admin,
  # and one open late must not be shut by a schedule row.
  def accepting_orders?
    kept? && status_active? && is_open?
  end

  def verified?
    verified_at.present?
  end

  def open_hours_for(day_of_week)
    opening_hours.where(day_of_week: day_of_week).order(:opens_at)
  end

  def commission_on(food_total)
    (food_total * commission_rate).round(2)
  end

  private

  # A restaurant that is gone must not leave an orderable menu behind.
  def discard_dependents!
    now = Time.current
    menu_items.kept.update_all(deleted_at: now)
    menu_categories.kept.update_all(deleted_at: now)
  end
end
