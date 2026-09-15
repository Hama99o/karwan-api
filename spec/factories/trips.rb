FactoryBot.define do
  # The second demand type. Schema and rules only — there is no trip product
  # yet, so these fixtures exist to hold the money and state rules honest, not
  # to drive screens.
  factory :trip do
    passenger { create(:user, :customer) }
    courier { nil }

    # Shar-e-Naw to Kabul airport, roughly.
    pickup_latitude   { 34.5400 }
    pickup_longitude  { 69.1750 }
    pickup_landmark_note { "Blue gate near Shar-e-Naw park" }
    dropoff_latitude  { 34.5658 }
    dropoff_longitude { 69.2123 }
    dropoff_landmark_note { "Airport departures" }

    passenger_phone { passenger.phone }
    distance_km { 4.2 }
    duration_minutes { 14 }

    # base 50 + 4.2km * 25 = 155, at 12.5% commission.
    fare             { 155 }
    commission       { 19.38 }
    courier_earnings { 135.62 }
    currency { "AFN" }

    payment_method { :cash }
    status { :requested }
    payment_status { :pending }
    requested_at { Time.current }

    trait :accepted do
      status { :accepted }
      courier { create(:user, :trip_courier) }
      accepted_at { Time.current }
    end

    trait :arrived do
      status { :arrived }
      courier { create(:user, :trip_courier) }
      accepted_at { 4.minutes.ago }
      arrived_at { Time.current }
    end

    trait :in_progress do
      status { :in_progress }
      courier { create(:user, :trip_courier) }
      arrived_at { 6.minutes.ago }
      started_at { Time.current }
    end

    trait :completed do
      status { :completed }
      courier { create(:user, :trip_courier) }
      started_at { 15.minutes.ago }
      completed_at { Time.current }
      payment_status { :collected }
    end

    trait :cancelled do
      status { :cancelled }
      cancelled_at { Time.current }
      cancellation_reason { :passenger_changed_mind }
      cancelled_by_role { :customer }
    end

    trait :failed do
      status { :failed }
      courier { create(:user, :trip_courier) }
      failed_at { Time.current }
      failure_reason { :passenger_no_show }
    end

    trait :settled do
      payment_status { :settled }
      settled_at { Time.current }
    end

    trait :overdue do
      requested_at { (Trip::TIMEOUTS[:requested] + 1.minute).ago }
      created_at { (Trip::TIMEOUTS[:requested] + 1.minute).ago }
      updated_at { (Trip::TIMEOUTS[:requested] + 1.minute).ago }
    end
  end
end
