require "administrate/base_dashboard"

class UserDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    phone: Field::String,
    name: Field::String,
    locale: Field::Select.with_options(collection: ->(_f) { User::LOCALES }),
    last_active_role: Field::Select.with_options(collection: ->(_f) { User.last_active_roles.keys }),
    status: Field::Select.with_options(collection: ->(_f) { User.statuses.keys }),
    phone_verified_at: Field::DateTime,
    user_roles: Field::HasMany,
    addresses: Field::HasMany,
    courier_profile: Field::HasOne,
    courier_wallet: Field::HasOne,
    # Reachable from the person, because "he says he worked all day" is asked
    # about a courier rather than about a shift id.
    courier_shifts: Field::HasMany,
    # Counts and dates, never a credential — see User#live_session_count.
    # `searchable: false` on both, and the reason is not style: Administrate
    # builds its search as a SQL LIKE over every string attribute, and these two
    # are COMPUTED METHODS rather than columns. Without it, searching users dies
    # on `column users.registered_devices_summary does not exist` — which is how
    # the full suite caught it after the admin folder alone had passed.
    live_session_count: Field::Number.with_options(searchable: false),
    registered_devices_summary: Field::String.with_options(searchable: false),
    # A THIRD computed method, and `searchable: false` for the reason stated
    # above rather than by imitation: Administrate would put
    # `users.delivery_failures_summary` into a SQL LIKE and searching users
    # would die. The comment three lines up is the record of that exact bug.
    delivery_failures_summary: Field::String.with_options(searchable: false),
    deleted_at: Field::DateTime,
    created_at: Field::DateTime
  }.freeze

  # `deleted_at` in the list for the same reason as on MerchantDashboard: a
  # discarded courier is already listed here and looked live.
  COLLECTION_ATTRIBUTES = %i[phone name last_active_role status deleted_at created_at].freeze
  SHOW_PAGE_ATTRIBUTES = %i[
    phone name locale last_active_role status phone_verified_at
    live_session_count registered_devices_summary delivery_failures_summary
    user_roles addresses
    courier_profile courier_wallet courier_shifts deleted_at created_at
  ].freeze
  FORM_ATTRIBUTES = %i[name locale status].freeze

  COLLECTION_FILTERS = {
    couriers: ->(resources) { resources.with_role(:courier) },
    merchant_owners: ->(resources) { resources.with_role(:merchant_owner) },
    suspended: ->(resources) { resources.where(status: :suspended) },
    # ── THE PEOPLE WORTH A CONVERSATION ───────────────────────────────────
    #
    # `TRUST_AND_REPUTATION.md` §2: the courier's problem reports *"should
    # accumulate against the customer"*, and the thing that makes it actionable
    # is *"four wrong addresses is a conversation Hamma9900 can have"*.
    #
    # ANY failure, not a threshold. What to do at four is a POLICY and §5 —
    # cancellation — is explicitly the next design conversation, so this lists
    # who to look at and decides nothing about them. One `EXISTS`, not a count
    # per row.
    had_a_failure: lambda { |resources|
      # `::Order`, NOT `Order`. Inside a dashboard the bare constant resolves to
      # **`Administrate::Order`** — the gem's own sort-direction class — and the
      # lambda dies with `undefined method 'where' for class
      # Administrate::Order`. The page still renders 200 with ZERO ROWS, so a
      # filter broken this way is indistinguishable from one that matched
      # nothing. Measured: this returned 0 while a customer with a recorded
      # failure was on the very next page.
      resources.where(id: ::Order.where(status: :failed).where.not(failure_reason: nil).select(:customer_id))
    }
  }.freeze

  def display_resource(user)
    user.display_name
  end
end
