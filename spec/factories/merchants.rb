FactoryBot.define do
  # find_or_create, because the slug is unique and every merchant needs a kind:
  # a sequence would create a hundred throwaway kinds across a suite run.
  factory :merchant_kind do
    slug { "restaurant" }
    name_en { "Restaurant" }
    name_fa { "رستوران" }
    name_ps { "رستوران" }
    position { 0 }
    is_active { true }

    trait :store do
      slug { "store" }
      name_en { "Store" }
      name_fa { "دکان" }
      name_ps { "دوکان" }
    end

    trait :pharmacy do
      slug { "pharmacy" }
      name_en { "Pharmacy" }
      name_fa { "دواخانه" }
      name_ps { "دواخانه" }
    end

    trait :bookshop do
      slug { "bookshop" }
      name_en { "Bookshop" }
      name_fa { "کتاب‌فروشی" }
      name_ps { "کتاب پلورنځی" }
    end
  end

  factory :merchant_category do
    sequence(:slug) { |n| "merchant_category-#{n}" }
    sequence(:name_en) { |n| "MerchantCategory #{n}" }
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

  factory :merchant do
    merchant_kind { MerchantKind.find_by(slug: "restaurant") || create(:merchant_kind) }
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

    # A merchant that sells goods rather than meals. Its prep time is nil,
    # because a book is picked off a shelf.
    trait :store do
      merchant_kind { MerchantKind.find_by(slug: "store") || create(:merchant_kind, :store) }
      prep_time_minutes { nil }
      name { "Kabul Book Store" }
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

    # A merchant you can actually place an order at: one category, one
    # available item. Most order specs need this and nothing more.
    trait :with_menu do
      after(:create) do |merchant|
        category = create(:catalog_category, merchant: merchant)
        create(:catalog_item, merchant: merchant, catalog_category: category)
      end
    end
  end

  factory :merchant_opening_hour do
    merchant
    day_of_week { 0 }
    opens_at { "09:00" }
    closes_at { "22:00" }
  end

  factory :merchant_category_assignment do
    merchant
    merchant_category
  end
end
