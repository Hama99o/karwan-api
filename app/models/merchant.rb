class Merchant < ApplicationRecord
  include AttachableDocuments
  include SoftDeletable
  include TrigramSearchable
  include Searchable

  # `lead` is a shop that asked us, through the app, and that nobody has called
  # yet. A lead IS a merchant awaiting verification — the same row in an earlier
  # state — so it lives here rather than in a table of its own: the console
  # Hamma9900 already watches is the call list, and onboarding is then
  # continuous. He calls them, fills in the rest of THIS row, assigns the owner,
  # and `sync_owner_role` grants the role.
  #
  # Distinct from `pending`, which means "we are onboarding this one". The
  # difference is whether a human has spoken to them, which is exactly what a
  # worklist needs to sort by.
  enum :status, { pending: 0, active: 1, suspended: 2, rejected: 3, lead: 4 }, prefix: true

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

  # ── VARIANTS, BECAUSE THE ORIGINAL IS THE USER'S MONEY ───────────────────
  #
  # Measured 2026-09-18 (docs/NOTES.md): a merchant card carries BOTH of these,
  # the default page is 20, and `MAX_IMAGE_BYTES` is 5 MB — so one Home screen
  # could pull ~200 MB of originals to render a logo at about 96 px. With
  # variants the same screen is ~1 MB.
  #
  # The sizes come from the rendered size in device pixels, measured from the
  # layout tree — not from a guess at a "reasonable" size. The logo draws at
  # ~96 px; the storefront card is 996 device px on a 1080/420 handset.
  has_one_attached :logo do |attachable|
    attachable.variant :thumb, resize_to_limit: [ 192, 192 ], saver: { quality: 80 }
  end

  # 1000 px AT q72, from a measurement rather than anybody's judgement —
  # including mine, which was wrong.
  #
  # This first shipped at 400 px, argued as "three megabytes is a lot of
  # somebody's credit for a sharper thumbnail". That framed a RATIO as a taste
  # question. The card renders at 996 device px, so:
  #
  #    400 px  1.29 MB/screen  2.49x UNDERSAMPLED — visibly soft, first screen
  #    800 px  4.19 MB/screen  1.24x undersampled — still soft
  #    996 q80 5.94 MB/screen  exact
  #   1000 q72 5.01 MB/screen  exact
  #
  # The rule is rendered width x DPR, then the smallest variant at or above it.
  # **800 does not satisfy it.** Dropping quality to 72 buys the exact
  # dimensions for roughly what 800 px at q80 would have cost, and correct
  # sampling at q72 beats q80 stretched 1.24x — upscaling softens everything,
  # while JPEG artefacts stay local.
  #
  # IT IS STILL 5 MB OF SOMEBODY'S CREDIT, and that number only holds if the
  # client loads all twenty cards at once. A list that loads images as they
  # scroll pays for the two or three on screen — under 1 MB — which is a bigger
  # win than any variant size and is a mobile-side question, not this one.
  #
  # A larger variant for the merchant DETAIL screen is worth having and is a
  # separate field — a contract change — so it waits for the paired commit.
  has_one_attached :storefront_photo do |attachable|
    attachable.variant :card, resize_to_limit: [ 1000, 750 ], saver: { quality: 72 }
  end

  # NO VARIANT, deliberately. The licence is never sent to a phone — it exists
  # for an operator verifying a shop in the console, on a laptop, where the
  # detail IS the point and a resize would defeat the review. Same reasoning
  # keeps the courier's tazkira, selfie and vehicle photo at full size.
  has_one_attached :license_photo

  # `has_one_attached` validates neither type nor size. The storefront photo is
  # downloaded by every customer who opens the app, on a connection where data
  # costs them real money (AFGHAN_UX.md §5) — so a 12 MB upload here is a bill
  # paid by every user, not just a large file on our disk.
  validates_attached :logo, :storefront_photo, :license_photo

  # ── WHEN DOES THIS SHOP OPEN NEXT? ──────────────────────────────────────
  #
  # The browse card's question, and the reason the list carries this rather
  # than a week of rows: twenty merchants times seven days is a payload nobody
  # reads to answer one question.
  #
  # NIL HAS TWO MEANINGS AND THE PAYLOAD SEPARATES THEM, because the card says
  # different things:
  #
  #   no hours at all   -> `hours_known: false`  -> "hours not given, ring them"
  #   inside its hours  -> `hours_known: true`, nil -> nothing to say
  #   outside its hours -> a time                -> "opens at ۸:۰۰"
  #
  # A shop that is MANUALLY closed inside its own opening hours returns nil on
  # purpose. `is_open` is the authority and hours are advisory, so the schedule
  # cannot tell us when a shopkeeper who shut early will reopen — and guessing
  # "tomorrow at 08:00" would be a worse answer than none.
  #
  # Returned as a full time rather than "08:00" so the app can render it in the
  # Shamsi calendar and say "tomorrow" when it is tomorrow — AFGHAN_UX makes
  # both the client's job, and neither is possible from a bare clock face.
  def next_opens_at(from = Time.zone.now)
    rows = opening_hours.to_a
    return nil if rows.empty?
    return nil if open_per_schedule?(from, rows)

    8.times do |offset|
      date = from.to_date + offset
      rows.select { |hours| hours.day_of_week == date.wday }
          .map { |hours| Time.zone.local(date.year, date.month, date.day, hours.opens_at.hour, hours.opens_at.min) }
          .sort
          .each { |candidate| return candidate if candidate > from }
    end

    nil
  end

  def hours_known?
    opening_hours.any?
  end

  # ASSIGNING AN OWNER IS WHAT GRANTS THE MERCHANT ROLE.
  #
  # It granted nothing. `owner_id` is set through the console's generic form, so
  # the launch-day sequence was: Hamma9900 sits with a restaurant owner,
  # onboards them, sets the owner to their phone — and that person signs in and
  # cannot reach the merchant tab. Worse than a clean failure, because
  # `OrderPolicy::MerchantScope` keys on `merchants.owner_id` and would resolve
  # while the role-gated endpoints refused, so the symptom points at the app
  # rather than at a missing `user_roles` row.
  #
  # This is the same bug courier approval had — status set, wallet made, role
  # never granted — on the path Hamma9900 uses FIRST, because merchants are
  # admin-onboarded and couriers self-apply.
  #
  # ON THE MODEL, NOT IN THE CONTROLLER, because the owner can be set from the
  # Administrate form, a seed, a console, or any admin path added later. A
  # callback is the only place that catches all of them.
  after_save :sync_owner_role, if: :saved_change_to_owner_id?

  validates :name, presence: true
  validates :phone, presence: true
  # Nullable: a book has no preparation time. Validated only when given, so a
  # non-food merchant carries no meaningless number.
  validates :prep_time_minutes, numericality: { greater_than: 0 }, allow_nil: true
  validates :commission_rate, numericality: { greater_than_or_equal_to: 0, less_than: 1 }

  scope :listed,       -> { kept.status_active }
  # The call list: shops that asked and have not been spoken to.
  scope :leads,        -> { kept.status_lead }
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

  # Inside a window ACCORDING TO THE SCHEDULE — which is not the same as open.
  # `is_open` decides whether orders are accepted; this only says whether the
  # posted hours cover right now.
  def open_per_schedule?(at, rows)
    rows.any? do |hours|
      next false unless hours.day_of_week == at.to_date.wday

      minutes = (at.hour * 60) + at.min
      minutes >= (hours.opens_at.hour * 60) + hours.opens_at.min &&
        minutes < (hours.closes_at.hour * 60) + hours.closes_at.min
    end
  end

  # A merchant that is gone must not leave an orderable menu behind.
  def discard_dependents!
    now = Time.current
    catalog_items.kept.update_all(deleted_at: now)
    catalog_categories.kept.update_all(deleted_at: now)
  end
  private

  # Grants the role to the new owner and takes it from the old one — but only
  # when that person owns nothing else, because one person can hold two
  # restaurants and reassigning one must not lock them out of the other.
  #
  # The customer role rides along with the grant (`User#grant_role!`) and is
  # never taken away by the revoke: a former owner still buys kebabs.
  def sync_owner_role
    previous_owner_id, new_owner_id = saved_change_to_owner_id

    User.find_by(id: new_owner_id)&.grant_role!(:merchant_owner)

    previous_owner = User.find_by(id: previous_owner_id)
    return if previous_owner.nil?
    return if previous_owner.owned_merchants.kept.exists?

    previous_owner.revoke_role!(:merchant_owner)
  end
end
