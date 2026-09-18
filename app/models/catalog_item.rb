class CatalogItem < ApplicationRecord
  include AttachableDocuments
  include Monetary
  include SoftDeletable
  include TrigramSearchable
  include Searchable

  belongs_to :merchant
  belongs_to :catalog_category, inverse_of: :catalog_items

  has_many :options, -> { order(:position) }, class_name: CatalogItemOption.name,
           dependent: :destroy, inverse_of: :catalog_item
  # Nullified, not destroyed: order_items reference this for provenance only and
  # carry their own name/price snapshot, so deleting a menu item must not delete
  # order history.
  has_many :order_items, dependent: :nullify

  # AFGHAN_UX.md puts the photo at the centre of this screen — a large share of
  # users cannot read fluently, so the photo IS the label. That makes the answer
  # a variant and never fewer photos.
  #
  # 1000 px AT q72, MEASURED. The menu item card dumped at **996 device px** —
  # identical to the storefront — so 400 px was undersampled by the same 2.49x
  # and the same arithmetic gives the same answer: rendered width x DPR, then
  # the smallest variant at or above it.
  #
  # It matters more here than on the Home cards. A soft storefront is a polish
  # complaint; a soft dish is a customer ordering the wrong food, because
  # AFGHAN_UX makes this photo the LABEL rather than decoration.
  has_one_attached :photo do |attachable|
    attachable.variant :card, resize_to_limit: [ 1000, 750 ], saver: { quality: 72 }
  end
  # Same reasoning as the merchant's storefront: this image is fetched by every
  # customer who opens the menu.
  # HOW BIG IT IS, and the merchant is the only one who knows. A restaurant
  # never touches this — food is always `small`, which is the default — and a
  # furniture shop sets `bulky` on beds once. It decides which vehicles can be
  # offered the order (`VehicleTypes::CARRIES`), so getting it wrong sends a
  # bicycle to collect a bed.
  enum :size_class, SizeClasses::ALL, prefix: :size

  validates_attached :photo

  validates :name, presence: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }
  validates :prep_time_minutes, numericality: { greater_than: 0 }, allow_nil: true

  scope :available, -> { kept.where(is_available: true) }
  scope :ordered,   -> { order(:position, :id) }

  # Multi-word, each word narrowing, each word matching the dish name or its
  # description — "chicken kabab" should not need to be a single stored string.
  def self.search(query)
    return all if query.blank?

    query.to_s.strip.split(/\s+/).reduce(all) do |result, word|
      term = "%#{word.downcase}%"
      result.where(
        "LOWER(COALESCE(catalog_items.search_text, catalog_items.name)) LIKE :t " \
        "OR LOWER(COALESCE(catalog_items.description, '')) LIKE :t",
        t: term
      )
    end
  end

  # Typo/transliteration fallback, ranked by closeness.
  def self.fuzzy(query)
    fuzzy_on(:search_text, query)
  end

  # The item's own prep time if set, else the merchant's — and nil for anything
  # that is not prepared. A book has no prep time and must not inherit a
  # kitchen's.
  def effective_prep_time_minutes
    prep_time_minutes || merchant.effective_prep_time_minutes
  end

  # Keep the denormalised merchant_id honest — it is what every scope filters
  # on, so a row where it disagrees with the category is invisible to the menu
  # it belongs to.
  before_validation :inherit_merchant_from_category

  private

  def inherit_merchant_from_category
    self.merchant_id ||= catalog_category&.merchant_id
  end
end
