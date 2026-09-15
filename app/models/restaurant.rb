class Restaurant < ApplicationRecord
  enum :status, { pending: 0, active: 1, suspended: 2 }, prefix: true

  # Nullable: admin onboards restaurants, so one exists before its owner has an
  # account. Restaurants are not self-serve in v0.
  belongs_to :owner, class_name: User.name, optional: true, inverse_of: :owned_restaurants

  has_many :opening_hours, class_name: RestaurantOpeningHour.name, dependent: :destroy,
                           inverse_of: :restaurant
  has_many :menu_categories, -> { order(:position) }, dependent: :destroy, inverse_of: :restaurant
  has_many :menu_items, dependent: :destroy
  has_many :orders, dependent: :restrict_with_error

  validates :name, presence: true
  validates :phone, presence: true
  validates :prep_time_minutes, numericality: { greater_than: 0 }
  validates :commission_rate, numericality: { greater_than_or_equal_to: 0, less_than: 1 }

  scope :listed,      -> { status_active }
  scope :orderable,   -> { status_active.where(is_open: true) }
  scope :alphabetical, -> { order(:name) }

  def self.search(query)
    return all if query.blank?

    query.to_s.strip.split(/\s+/).reduce(all) do |result, word|
      result.where("LOWER(name) LIKE ?", "%#{word.downcase}%")
    end
  end

  # `is_open` is a MANUAL toggle and is the authority. Opening hours are
  # advisory — they tell a customer when to come back, they do not open the
  # restaurant. A restaurant that forgot to close must be closeable by admin,
  # and a restaurant open late must not be shut by a schedule row.
  def accepting_orders?
    status_active? && is_open?
  end

  def open_hours_for(day_of_week)
    opening_hours.where(day_of_week: day_of_week).order(:opens_at)
  end
end
