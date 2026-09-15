FactoryBot.define do
  factory :menu_category do
    restaurant
    name { "Kebabs" }
    position { 0 }

    trait :discarded do
      deleted_at { Time.current }
    end
  end

  factory :menu_item do
    menu_category
    # Left to the model's before_validation, which inherits restaurant_id from
    # the category — exercising that hook rather than working around it.
    restaurant { nil }
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
        size = create(:menu_item_option, menu_item: item, name: "Size", selection_type: :single, required: true)
        create(:menu_item_option_value, menu_item_option: size, name: "Regular", price_delta: 0)
        create(:menu_item_option_value, menu_item_option: size, name: "Large", price_delta: 100)

        extras = create(:menu_item_option, menu_item: item, name: "Extras", selection_type: :multiple, max_selections: 3)
        create(:menu_item_option_value, menu_item_option: extras, name: "Extra naan", price_delta: 20)
      end
    end
  end

  factory :menu_item_option do
    menu_item
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

  factory :menu_item_option_value do
    menu_item_option
    name { "Large" }
    price_delta { 100 }
    currency { "AFN" }
    is_available { true }
    position { 0 }
  end
end
