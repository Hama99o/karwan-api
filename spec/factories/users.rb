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

    # ── A FIXTURE THAT CAN SIGN IN THE WAY A REAL USER DOES ──────────────────
    #
    # Every account registration produces has a password, so a factory whose
    # users have none builds a person the app can no longer create — the same
    # trap `docs/TESTING.md` records and the same one the `merchant_owner`
    # comment below cost an afternoon over. Cheap here: Devise stretches are 1
    # in test (config/initializers/devise.rb), so this is not the 1,400-example
    # bcrypt tax it would be at 12.
    password { "a-long-test-password" }

    # AN ACCOUNT FROM BEFORE PASSWORDS EXISTED. Real, and it must stay
    # expressible: `encrypted_password` defaults to "" rather than being
    # backfilled, so every account that signed in with a code has one. It can
    # reset, and until it does it must not be TOLD APART from a wrong password
    # — see the sign-in spec.
    trait :passwordless do
      password { nil }
    end

    trait :unverified do
      phone_verified_at { nil }
    end

    trait :suspended do
      status { :suspended }
    end

    trait :discarded do
      deleted_at { Time.current }
    end

    # EVERY PARTNER TRAIT GRANTS THROUGH `grant_role!`, not by writing a
    # `user_roles` row directly — because the rule that any partner role
    # carries `customer` alongside it lives in that method, and a factory that
    # sidesteps it builds a user the app can no longer produce. It cost an
    # afternoon once: a courier with no customer role could not be given a
    # session in the customer tab, and the test that found it looked like a
    # bug in the code rather than in its fixtures.
    trait :customer do
      after(:create) { |user| user.grant_role!(:customer) }
    end

    # The supply side, for both demand types. One human, one wallet, one
    # commission — the UI calls them a rider in the food tab and a driver in
    # the ride tab.
    trait :courier do
      last_active_role { :courier }
      after(:create) do |user|
        user.grant_role!(:courier)
        create(:courier_profile, :approved, user: user)
        create(:courier_wallet, user: user)
      end
    end

    trait :ride_courier do
      last_active_role { :courier }
      after(:create) do |user|
        user.grant_role!(:courier)
        create(:courier_profile, :approved, user: user, accepted_job_kinds: [ "ride" ])
        create(:courier_wallet, user: user)
      end
    end

    trait :merchant_owner do
      last_active_role { :merchant_owner }
      after(:create) { |user| user.grant_role!(:merchant_owner) }
    end

    trait :admin do
      last_active_role { :admin }
      after(:create) { |user| user.grant_role!(:admin) }
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
