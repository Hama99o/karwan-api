require "rails_helper"

# THE RECEIPT MUST SURVIVE THE MENU.
#
# One-way door #1: an order's lines are a snapshot, so a restaurant editing its
# menu cannot rewrite what somebody bought. Adding
# `catalog_item_option_value_id` for re-ordering put a live reference next to
# that snapshot, and a live reference is exactly how the snapshot rule gets
# broken by accident — through a convenience clause on a foreign key rather
# than through anybody deciding to break it.
#
# `on_delete: :cascade` here would DELETE the itemised receipt for a completed
# order when a merchant tidied their menu. The default, NO ACTION, would make
# an option value undeletable once anyone had ordered it, surfacing as a 500.
# `:nullify` is neither, and these examples are what keep it that way.
RSpec.describe OrderItemOption do
  let(:merchant) { create(:merchant) }
  let(:category) { create(:catalog_category, merchant: merchant) }
  let(:item) { create(:catalog_item, catalog_category: category, merchant: merchant, price: 400) }
  let(:option) do
    item.options.create!(name: "Size", selection_type: :single, required: true,
                         min_selections: 1, max_selections: 1)
  end
  let(:large) { option.values.create!(name: "Large", price_delta: 100, currency: "AFN") }

  let(:order_item) { create(:order_item, catalog_item: item, name: item.name) }
  let!(:chosen) do
    order_item.selected_options.create!(
      option_name: option.name, value_name: large.name,
      price_delta: large.price_delta, currency: "AFN",
      catalog_item_option_value: large
    )
  end

  it "records which value was chosen, so a past order can be re-ordered exactly" do
    expect(chosen.catalog_item_option_value).to eq(large)
  end

  # THE ONE THAT MATTERS. A merchant removing "Large" from today's menu must
  # not touch a completed order's receipt.
  it "keeps the receipt when the merchant DELETES the option value" do
    large.destroy!

    chosen.reload
    # The snapshot — what was bought and for how much — is untouched.
    expect(chosen.option_name).to eq("Size")
    expect(chosen.value_name).to eq("Large")
    expect(chosen.price_delta).to eq(100)
    # Only the re-order shortcut is lost.
    expect(chosen.catalog_item_option_value_id).to be_nil
  end

  # Deleting a menu option is ordinary housekeeping. If a past order could
  # block it, a merchant would hit a 500 and an operator would have no action
  # to take.
  it "does not stop the merchant deleting it" do
    expect { large.destroy! }.not_to raise_error
  end

  # Every order placed before the column existed has it empty, and the
  # re-order path falls back to matching by name — the same road a nullified
  # row takes, which is why nullify was safe to choose.
  it "is valid with no reference at all, as every historical row is" do
    historical = order_item.selected_options.create!(
      option_name: "Size", value_name: "Small", price_delta: 0, currency: "AFN"
    )

    expect(historical).to be_valid
    expect(historical.catalog_item_option_value).to be_nil
  end

  # And the option value is HARD-deletable — it has no `deleted_at`, unlike
  # catalog_items. So nullify is load-bearing here rather than a precaution
  # against something the app never does.
  it "is guarding a real possibility — option values are not soft-deleted" do
    # by-design: a column list is never empty, so absence here is a real fact about the schema.
    expect(CatalogItemOptionValue.column_names).not_to include("deleted_at")
  end
end
