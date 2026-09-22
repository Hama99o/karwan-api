class CatalogCategory < ApplicationRecord
  include SoftDeletable
  belongs_to :merchant, inverse_of: :catalog_categories
  has_many :catalog_items, -> { order(:position) }, dependent: :destroy, inverse_of: :catalog_category

  validates :name, presence: true

  scope :ordered, -> { order(:position, :id) }

  # ── LOAD A WHOLE CATALOG IN ONE GO ────────────────────────────────────────
  #
  # The preload for every category at once, beside the method that consumes it
  # so the two cannot drift. `items_for_serialization` used to issue its own
  # query per category, and the public catalog controller ALSO declared this
  # `includes` — which was then thrown away, because calling `catalog_items.…`
  # on the association builds a fresh relation and ignores what was loaded.
  #
  # MEASURED before and after, on the busiest screen in the app:
  #
  #   categories  items   before   after
  #        3        6       30       8
  #        6       12       54       8
  #       12       24      102       8
  #
  # Linear in the catalogue, on a public unauthenticated endpoint a first-time
  # user hits before anything else — and 12 categories is a small menu. The old
  # comment was right about the inner loop, no N+1 per item or per option, and
  # silent about the outer one: the shape `docs/NOTES.md` keeps finding, a true
  # sentence about the part somebody looked at.
  # `merchant: :merchant_kind` is not decoration either, and it was the LARGER
  # of the two N+1s here — per ITEM rather than per category. The serializer
  # asks each item for `effective_prep_time_minutes`, which is
  # `prep_time_minutes || merchant.effective_prep_time_minutes`, and that reads
  # `merchant_kind&.prepares_food?`. So **every dish re-loaded the shop it
  # belongs to, and that shop's kind** — for a catalog that has exactly one
  # merchant, already in memory. Eight dishes cost sixteen extra queries.
  #
  # It is invisible in the payload, which is why a captured fixture alone would
  # not have found it: the response is byte-identical either way. Only a query
  # count shows it.
  scope :with_items_for_serialization, lambda {
    includes(catalog_items: [ :photo_attachment, { merchant: :merchant_kind }, { options: :values } ])
  }

  # Sold-out items are INCLUDED and flagged, never filtered. A customer looking
  # for yesterday's kabab needs to see it is sold out today; removing it reads
  # as "this shop no longer sells it".
  #
  # Lives here rather than in the serializer so the preloading is one decision.
  # When the caller has already loaded the association — `with_items_for_serialization`
  # above — the discard filter and the ordering are applied IN MEMORY, because
  # re-asking the database for rows it has already sent is the N+1 this method
  # exists to prevent. The querying branch stays for any caller that has not.
  def items_for_serialization
    return catalog_items.kept.ordered.includes(:photo_attachment, options: :values) unless catalog_items.loaded?

    catalog_items.select(&:kept?).sort_by { |item| [ item.position || 0, item.id ] }
  end

  private

  def discard_dependents!
    catalog_items.kept.update_all(deleted_at: Time.current)
  end
end
