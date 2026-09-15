FactoryBot.define do
  factory :cuisine do
    sequence(:slug) { |n| "cuisine-#{n}" }
    sequence(:name_en) { |n| "Cuisine #{n}" }
    name_fa { "غذا" }
    name_ps { "خواړه" }
    position { 0 }
    is_active { true }

    trait :kabab do
      slug { "kabab" }
      name_en { "Kabab" }
      name_fa { "کباب" }
      name_ps { "کباب" }
    end
  end

  factory :restaurant do
    name { "#{Faker::Address.community} Kabab House" }
    sequence(:phone) { |n| "+9378#{n.to_s.rjust(7, '0')}" }
    is_open { true }
    status { :active }
    prep_time_minutes { 20 }
    # Kabul.
    latitude  { 34.5553 }
    longitude { 69.2075 }
    landmark_note { "Opposite the Shar-e-Naw mosque" }
    commission_rate { 0.125 }
    owner_name { Faker::Name.name }
    sequence(:owner_phone) { |n| "+9379#{n.to_s.rjust(7, '0')}" }
    contact_person_name { Faker::Name.name }

    trait :closed do
      is_open { false }
    end

    trait :pending do
      status { :pending }
    end

    trait :suspended do
      status { :suspended }
    end

    trait :verified do
      verified_at { Time.current }
      verified_by { create(:user, :admin) }
    end

    trait :discarded do
      deleted_at { Time.current }
    end

    # A restaurant you can actually place an order at: one category, one
    # available item. Most order specs need this and nothing more.
    trait :with_menu do
      after(:create) do |restaurant|
        category = create(:menu_category, restaurant: restaurant)
        create(:menu_item, restaurant: restaurant, menu_category: category)
      end
    end
  end

  factory :restaurant_opening_hour do
    restaurant
    day_of_week { 0 }
    opens_at { "09:00" }
    closes_at { "22:00" }
  end

  factory :restaurant_cuisine do
    restaurant
    cuisine
  end
end
