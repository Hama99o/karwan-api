FactoryBot.define do
  # The money here follows the brief's own worked example exactly, so a spec
  # reading it can be checked against the document: food 400, delivery 100,
  # commission 50, customer pays 500, restaurant is handed 350, courier keeps 100
  # and is left holding our 50.
  factory :order do
    customer { create(:user, :customer) }
    restaurant
    courier { nil }

    food_total        { 400 }
    delivery_fee      { 100 }
    commission        { 50 }
    courier_fee       { 100 }
    restaurant_payout { 350 }
    customer_total    { 500 }
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
      restaurant_paid_at { Time.current }
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
    menu_item { nil }
    name { "Chicken Kabab" }
    unit_price { 400 }
    options_total { 0 }
    quantity { 1 }
    line_total { 400 }
    currency { "AFN" }

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
    actor { create(:user, :restaurant_owner) }
    actor_role { :restaurant_owner }
    created_at { Time.current }

    # A nil actor means a timeout fired rather than a person acting — the
    # difference between "the restaurant rejected it" and "the restaurant never
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
