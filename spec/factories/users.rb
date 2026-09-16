FactoryBot.define do
  factory :user do
    # Afghan mobile numbers are +937xxxxxxxx. Sequenced rather than Faker'd
    # because the column is unique and Faker collides often enough to produce a
    # flaky suite.
    sequence(:phone) { |n| "+9377#{n.to_s.rjust(7, '0')}" }
    name { Faker::Name.name }
    locale { "fa" }
    last_active_role { :customer }
    status { :active }
    phone_verified_at { Time.current }

    trait :unverified do
      phone_verified_at { nil }
    end

    trait :suspended do
      status { :suspended }
    end

    trait :discarded do
      deleted_at { Time.current }
    end

    trait :customer do
      after(:create) { |user| create(:user_role, user: user, role: :customer) }
    end

    # The supply side, for both demand types. One human, one wallet, one
    # commission — the UI calls them a rider in the food tab and a driver in
    # the ride tab.
    trait :courier do
      last_active_role { :courier }
      after(:create) do |user|
        create(:user_role, user: user, role: :courier)
        create(:courier_profile, :approved, user: user)
        create(:courier_wallet, user: user)
      end
    end

    trait :ride_courier do
      last_active_role { :courier }
      after(:create) do |user|
        create(:user_role, user: user, role: :courier)
        create(:courier_profile, :approved, user: user, accepted_job_kinds: [ "ride" ])
        create(:courier_wallet, user: user)
      end
    end

    trait :merchant_owner do
      last_active_role { :merchant_owner }
      after(:create) { |user| create(:user_role, user: user, role: :merchant_owner) }
    end

    trait :admin do
      last_active_role { :admin }
      after(:create) { |user| create(:user_role, user: user, role: :admin) }
    end
  end

  factory :user_role do
    user
    role { :customer }
  end

  factory :address do
    user
    label { "Home" }
    # Shar-e-Naw, Kabul. Real coordinates matter: a distance sort of Afghan
    # fixtures against Mountain View orders them meaninglessly, which is a trap
    # already documented in hatiwal's QA handbook.
    latitude  { 34.5400 }
    longitude { 69.1750 }
    landmark_note { "Blue gate near Shar-e-Naw park, second floor" }
    phone { user.phone }
    is_default { false }

    trait :default do
      is_default { true }
    end

    trait :discarded do
      deleted_at { Time.current }
    end
  end
end

FactoryBot.define do
  # The ops console operator. A SEPARATE TABLE from `users` on purpose: this
  # person can cancel any order and credit any wallet, so a customer's session
  # token must never be able to reach them (config/routes.rb).
  factory :admin_user do
    sequence(:name) { |n| "Ops #{n}" }
    sequence(:email) { |n| "ops#{n}@karwan.af" }
    password { "a-long-test-password" }
  end
end
