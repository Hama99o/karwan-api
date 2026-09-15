FactoryBot.define do
  factory :catalog_category do
    merchant
    name { "Kebabs" }
    position { 0 }

    trait :discarded do
      deleted_at { Time.current }
    end
  end

  factory :catalog_item do
    catalog_category
    # Left to the model's before_validation, which inherits merchant_id from
    # the category — exercising that hook rather than working around it.
    merchant { nil }
    name { "Chicken Kabab" }
    description { "Charcoal grilled, served with naan" }
    price { 400 }
    currency { "AFN" }
    is_available { true }
    position { 0 }

    trait :sold_out do
      is_available { false }
    end

    trait :discarded do
      deleted_at { Time.current }
    end

    trait :with_options do
      after(:create) do |item|
        size = create(:catalog_item_option, catalog_item: item, name: "Size", selection_type: :single, required: true)
        create(:catalog_item_option_value, catalog_item_option: size, name: "Regular", price_delta: 0)
        create(:catalog_item_option_value, catalog_item_option: size, name: "Large", price_delta: 100)

        extras = create(:catalog_item_option, catalog_item: item, name: "Extras", selection_type: :multiple, max_selections: 3)
        create(:catalog_item_option_value, catalog_item_option: extras, name: "Extra naan", price_delta: 20)
      end
    end
  end

  factory :catalog_item_option do
    catalog_item
    name { "Size" }
    selection_type { :single }
    required { false }
    min_selections { 0 }
    position { 0 }

    trait :multiple do
      selection_type { :multiple }
      max_selections { 3 }
    end
  end

  factory :catalog_item_option_value do
    catalog_item_option
    name { "Large" }
    price_delta { 100 }
    currency { "AFN" }
    is_available { true }
    position { 0 }
  end
end
