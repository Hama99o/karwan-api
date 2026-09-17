FactoryBot.define do
  # The money here follows the brief's own worked example exactly, so a spec
  # reading it can be checked against the document: food 400, delivery 100,
  # commission 50, customer pays 500, merchant is handed 350, courier keeps 100
  # and is left holding our 50.
  factory :order do
    customer { create(:user, :customer) }
    merchant
    courier { nil }

    items_total        { 400 }
    delivery_fee      { 100 }
    commission        { 50 }
    courier_fee       { 100 }
    # DERIVED, not stated, so overriding `commission` or `items_total` in an
    # example keeps the row VALID. Stated as 350 it built an order whose
    # payout did not match its commission — a row the app cannot produce, and
    # `docs/TESTING.md`'s fourth question: could this database state occur
    # through the app? The `merchant_payout = items_total - commission`
    # validation caught four such fixtures the day it was added.
    merchant_payout { items_total - commission }
    customer_total { items_total + delivery_fee }
    currency { "AFN" }

    payment_method { :cash }
    status { :placed }
    payment_status { :pending }

    delivery_latitude  { 34.5400 }
    delivery_longitude { 69.1750 }
    delivery_landmark_note { "Blue gate near Shar-e-Naw park, second floor" }
    customer_phone { customer.phone }
    placed_at { Time.current }

    trait :accepted do
      status { :accepted }
      accepted_at { Time.current }
    end

    trait :preparing do
      status { :preparing }
      accepted_at { 5.minutes.ago }
      preparing_at { Time.current }
    end

    trait :ready do
      status { :ready }
      accepted_at { 20.minutes.ago }
      ready_at { Time.current }
    end

    trait :picked_up do
      status { :picked_up }
      courier { create(:user, :courier) }
      picked_up_at { Time.current }
      merchant_paid_at { Time.current }
    end

    trait :delivered do
      status { :delivered }
      courier { create(:user, :courier) }
      picked_up_at { 20.minutes.ago }
      delivered_at { Time.current }
      payment_status { :collected }
    end

    trait :failed do
      status { :failed }
      courier { create(:user, :courier) }
      failed_at { Time.current }
      failure_reason { :customer_refused }
    end

    trait :cancelled do
      status { :cancelled }
      cancelled_at { Time.current }
      cancellation_reason { :customer_changed_mind }
      cancelled_by_role { :customer }
    end

    trait :settled do
      payment_status { :settled }
      settled_at { Time.current }
    end

    # Deliberately far enough past the state's timeout to be overdue — used by
    # the specs that assert the admin board's staleness colouring.
    trait :overdue do
      placed_at { (Order::TIMEOUTS[:placed] + 1.minute).ago }
      created_at { (Order::TIMEOUTS[:placed] + 1.minute).ago }
      updated_at { (Order::TIMEOUTS[:placed] + 1.minute).ago }
    end

    trait :with_items do
      after(:create) do |order|
        create(:order_item, order: order, unit_price: 400, quantity: 1, line_total: 400)
      end
    end
  end

  factory :order_item do
    order
    # ── A REAL ORDER LINE POINTS AT A CATALOG ITEM ───────────────────────────
    #
    # This was `nil`, which describes a world the app cannot produce:
    # `Orders::PlaceService` always sets `catalog_item`, and catalog items are
    # SOFT deleted, so the pointer survives a delisting too. A line with no
    # pointer is reachable only for orders placed before the column existed.
    #
    # It mattered because "order this again" is built on that pointer, and a
    # fixture with none made every re-order example pass against nothing —
    # `docs/TESTING.md`: could this DB state occur through the app?
    #
    # Built from the ORDER'S OWN merchant, not a free-floating one, because a
    # line pointing at another shop's dish is the other impossible state.
    catalog_item do
      create(:catalog_item, catalog_category: create(:catalog_category, merchant: order.merchant),
                            name: name, price: unit_price)
    end
    name { "Chicken Kabab" }
    unit_price { 400 }
    options_total { 0 }
    quantity { 1 }
    line_total { 400 }
    currency { "AFN" }

    # THE ONE CASE THAT REALLY HAS NO POINTER: an order placed before the
    # column existed. Kept expressible because the serializer must render it
    # and the app must refuse to re-order it rather than crash.
    trait :delisted do
      catalog_item { nil }
    end

    trait :with_options do
      options_total { 100 }
      line_total { 500 }

      after(:create) do |item|
        create(:order_item_option, order_item: item, option_name: "Size",
                                   value_name: "Large", price_delta: 100)
      end
    end
  end

  factory :order_item_option do
    order_item
    option_name { "Size" }
    value_name { "Large" }
    price_delta { 100 }
    currency { "AFN" }
  end

  factory :status_transition do
    subject { create(:order) }
    # Strings, not enum symbols: the table is polymorphic over Order and Trip,
    # which have different status vocabularies.
    from_status { "placed" }
    to_status { "accepted" }
    actor { create(:user, :merchant_owner) }
    actor_role { :merchant_owner }
    created_at { Time.current }

    # A nil actor means a timeout fired rather than a person acting — the
    # difference between "the merchant rejected it" and "the merchant never
    # answered".
    trait :system do
      actor { nil }
      actor_role { nil }
      reason { "timeout" }
    end
  end

  factory :offer do
    offerable { create(:order) }
    courier { create(:user, :courier) }
    status { :offered }
    sequence(:sequence) { |n| n }
    offered_at { Time.current }
    expires_at { Offer::DEFAULT_TTL.from_now }

    trait :expired do
      expires_at { 1.second.ago }
    end

    trait :accepted do
      status { :accepted }
      responded_at { Time.current }
    end

    trait :declined do
      status { :declined }
      responded_at { Time.current }
    end

    trait :timed_out do
      status { :timed_out }
      expires_at { 1.minute.ago }
    end
  end
end
