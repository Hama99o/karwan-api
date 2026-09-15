class Merchant < ApplicationRecord
  include AttachableDocuments
  include SoftDeletable
  include TrigramSearchable
  include Searchable

  enum :status, { pending: 0, active: 1, suspended: 2, rejected: 3 }, prefix: true

  # Nullable: admin onboards merchants, so one exists before its owner has an
  # account. Merchants are not self-serve in v0.
  # A growable taxonomy, not an enum — see MerchantKind. The order flow, the
  # catalog, dispatch and the courier pool are identical across kinds; only the
  # words the UI uses change, which is a client concern.
  belongs_to :merchant_kind
  belongs_to :owner, class_name: User.name, optional: true, inverse_of: :owned_merchants
  # See CourierProfile for why there are two: the console operator is an
  # AdminUser, which cannot be assigned to a `User` association.
  belongs_to :verified_by, class_name: User.name, optional: true
  belongs_to :verified_by_admin_user, class_name: AdminUser.name, optional: true

  has_many :opening_hours, class_name: MerchantOpeningHour.name, dependent: :destroy,
                           inverse_of: :merchant
  has_many :catalog_categories, -> { order(:position) }, dependent: :destroy, inverse_of: :merchant
  has_many :catalog_items, dependent: :destroy
  has_many :merchant_category_assignments, dependent: :destroy
  has_many :merchant_categories, through: :merchant_category_assignments
  has_many :orders, dependent: :restrict_with_error

  has_one_attached :logo
  has_one_attached :storefront_photo
  has_one_attached :license_photo

  # `has_one_attached` validates neither type nor size. The storefront photo is
  # downloaded by every customer who opens the app, on a connection where data
  # costs them real money (AFGHAN_UX.md §5) — so a 12 MB upload here is a bill
  # paid by every user, not just a large file on our disk.
  validates_attached :logo, :storefront_photo, :license_photo

  validates :name, presence: true
  validates :phone, presence: true
  # Nullable: a book has no preparation time. Validated only when given, so a
  # non-food merchant carries no meaningless number.
  validates :prep_time_minutes, numericality: { greater_than: 0 }, allow_nil: true
  validates :commission_rate, numericality: { greater_than_or_equal_to: 0, less_than: 1 }

  scope :listed,       -> { kept.status_active }
  scope :orderable,    -> { listed.where(is_open: true) }
  scope :alphabetical, -> { order(:name) }
  scope :by_merchant_category,   ->(merchant_category_id) { joins(:merchant_category_assignments).where(merchant_category_assignments: { merchant_category_id: merchant_category_id }) }

  # People search for a DISH, not a merchant — "mantu" is food, not a shop.
  # So a merchant matches on its own name, on the name of any available dish
  # it sells, or on one of its merchant_categories.
  #
  # Multi-word: each word narrows the result, and each word may match any of the
  # three. This is the house rule from hatiwal-api's backend prompt, and it is
  # what makes "chicken kabab" behave the way a person expects.
  #
  # EXISTS subqueries rather than joins, deliberately: a join against catalog_items
  # returns one row per matching dish, so a merchant with four matching dishes
  # appears four times, and the DISTINCT you then reach for breaks ordering by
  # similarity later. EXISTS asks the only question being asked — is there one?
  def self.search(query)
    return all if query.blank?

    query.to_s.strip.split(/\s+/).reduce(all) do |result, word|
      term = "%#{word.downcase}%"
      result.where(
        "LOWER(COALESCE(merchants.search_text, merchants.name)) LIKE :t
         OR EXISTS (
              SELECT 1 FROM catalog_items mi
              WHERE mi.merchant_id = merchants.id
                AND mi.deleted_at IS NULL
                AND mi.is_available = TRUE
                AND LOWER(COALESCE(mi.search_text, mi.name)) LIKE :t
            )
         OR EXISTS (
              SELECT 1 FROM merchant_category_assignments rc
              JOIN merchant_categories c ON c.id = rc.merchant_category_id
              WHERE rc.merchant_id = merchants.id
                AND (LOWER(c.name_en) LIKE :t OR LOWER(c.name_fa) LIKE :t OR LOWER(c.name_ps) LIKE :t)
            )",
        t: term
      )
    end
  end

  # Fallback for when `search` returns nothing because of a typo or a different
  # transliteration. Ranked by similarity, so the closest spelling comes first.
  # Fuzzy over the cross-script column, so a different transliteration matches
  # as well as a typo.
  def self.fuzzy(query)
    fuzzy_on(:search_text, query)
  end

  # `is_open` is a MANUAL toggle and is the authority. Opening hours are
  # advisory — they tell a customer when to come back, they do not open the
  # merchant. A merchant that forgot to close must be closeable by admin,
  # and one open late must not be shut by a schedule row.
  def accepting_orders?
    kept? && status_active? && is_open?
  end

  def verified?
    verified_at.present?
  end

  # Only meaningful for a merchant that prepares food. Nil elsewhere, and
  # callers must treat nil as "not applicable" rather than as zero.
  def effective_prep_time_minutes
    return nil unless merchant_kind&.prepares_food?

    prep_time_minutes
  end

  def open_hours_for(day_of_week)
    opening_hours.where(day_of_week: day_of_week).order(:opens_at)
  end

  def commission_on(items_total)
    (items_total * commission_rate).round(2)
  end

  private

  # A merchant that is gone must not leave an orderable menu behind.
  def discard_dependents!
    now = Time.current
    catalog_items.kept.update_all(deleted_at: now)
    catalog_categories.kept.update_all(deleted_at: now)
  end
end
