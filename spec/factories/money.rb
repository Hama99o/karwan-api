FactoryBot.define do
  factory :courier_profile do
    user
    is_available { false }
    vehicle_type { :motorbike }
    verification_status { :pending }
    accepted_job_kinds { [ "food_order" ] }
    full_name { Faker::Name.name }
    father_name { Faker::Name.first_name }
    sequence(:national_id_number) { |n| "1400#{n.to_s.rjust(8, '0')}" }
    guarantor_name { Faker::Name.name }
    sequence(:guarantor_phone) { |n| "+9376#{n.to_s.rjust(7, '0')}" }
    guarantor_relation { "cousin" }
    work_area { "Shar-e-Naw" }

    trait :approved do
      verification_status { :approved }
      verified_at { Time.current }
      verified_by { create(:user, :admin) }
    end

    trait :available do
      is_available { true }
      last_latitude  { 34.5553 }
      last_longitude { 69.2075 }
      location_updated_at { Time.current }
    end

    trait :stale_location do
      last_latitude  { 34.5553 }
      last_longitude { 69.2075 }
      location_updated_at { (CourierProfile::STALE_AFTER + 1.minute).ago }
    end

    trait :dispatchable do
      approved
      available
    end

    trait :takes_trips do
      accepted_job_kinds { [ "trip" ] }
    end

    trait :takes_both do
      accepted_job_kinds { [ "food_order", "trip" ] }
    end

    trait :takes_nothing do
      accepted_job_kinds { [] }
    end
  end

  factory :courier_wallet do
    user
    balance { 1000 }
    credit_line { 500 }
    currency { "AFN" }

    trait :empty do
      balance { 0 }
    end

    # At the floor exactly — the boundary where the app must stop assigning
    # work, which is the case most likely to be got wrong by one.
    trait :at_floor do
      balance { -500 }
      credit_line { 500 }
    end

    trait :below_floor do
      balance { -600 }
      credit_line { 500 }
    end
  end

  factory :wallet_entry do
    courier_wallet
    kind { :top_up }
    amount { 1000 }
    currency { "AFN" }
    balance_after { 1000 }
    recorded_by { create(:user, :admin) }
    created_at { Time.current }

    trait :commission do
      kind { :commission }
      amount { -50 }
      balance_after { 950 }
    end

    trait :reimbursement do
      kind { :reimbursement }
      amount { 400 }
    end
  end

  factory :settlement do
    courier { create(:user, :courier) }
    expected_amount { 500 }
    counted_amount { 500 }
    currency { "AFN" }
    counted_by_name { "Najibullah (Kabul office)" }
    counted_by { nil }
    settled_at { Time.current }

    trait :short do
      counted_amount { 450 }
    end

    trait :over do
      counted_amount { 550 }
    end
  end

  factory :setting do
    sequence(:key) { |n| "setting_#{n}" }
    value { "1" }
    value_type { :integer }
  end

  factory :audit_log do
    actor { create(:user, :admin) }
    actor_role { :admin }
    action { "order.cancelled" }
    target { nil }
    created_at { Time.current }
  end
end
