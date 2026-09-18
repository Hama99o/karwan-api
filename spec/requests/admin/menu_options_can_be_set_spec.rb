require "rails_helper"

# ═══ "LARGE, +100" HAD NO WAY IN ═══════════════════════════════════════════
#
# CLAUDE.md's v0 data model lists `menu_item_options` and their values, and says
# of them in the sharpest terms in that document: **"This is bigger than it
# looks; keep it simple but do not skip it."**
#
# It was not skipped. The models, the cart resolver, the order-time snapshot,
# `OrderItem#options_summary` on the console and the customer's payload were all
# built. **Nothing could create one.** The merchant API only reads them —
# `includes(catalog_items: { options: :values })` — there was no console door,
# and every option in every database came from a seed.
#
# So a restaurant selling "Chicken Kabab, large, +100" could not say so, while
# every layer downstream stood ready to carry it. The third instance of one
# shape today, found by `bin/console_doors` pointed at its own leftovers: a read
# path whose write path does not exist.
RSpec.describe "an operator can set a dish's options", type: :request do
  let(:admin) do
    AdminUser.create!(name: "Najibullah", email: "ops@karwan.af", password: "a-long-test-password")
  end

  before do
    post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
  end

  let!(:merchant) { create(:merchant, name: "Kabab House", is_open: true) }
  let!(:category) { create(:catalog_category, merchant: merchant) }
  let!(:item) { create(:catalog_item, catalog_category: category, merchant: merchant, name: "Chicken Kabab", price: 400) }

  it "offers a form at all, which is what was missing" do
    get "/admin/catalog_item_options/new"

    expect(response).to have_http_status(:ok)
  end

  it "creates an option and its values, and the customer's menu carries them" do
    expect {
      post "/admin/catalog_item_options", params: {
        catalog_item_option: {
          catalog_item_id: item.id, name: "Size", selection_type: "single",
          required: true, min_selections: 1, max_selections: 1, position: 1
        }
      }
    }.to change(CatalogItemOption, :count).by(1)

    option = CatalogItemOption.order(:id).last

    post "/admin/catalog_item_option_values", params: {
      catalog_item_option_value: {
        catalog_item_option_id: option.id, name: "Large", price_delta: "100",
        is_available: true, position: 1
      }
    }

    # THE HALF THAT MAKES IT WORTH ANYTHING. A console that writes options no
    # customer is offered is the dead path this replaces.
    get "/api/v1/public/merchants/#{merchant.id}/catalog"

    served = JSON.parse(response.body).dig("catalogs", 0, "items", 0, "options", 0)
    expect(served).to be_present, "the customer's menu carries no options for a dish that has one"
    expect(served["name"]).to eq("Size")
    expect(served["values"].map { |v| v["name"] }).to include("Large")
  end

  # "no rice, −20" is a real menu line and the model allows it. A console that
  # silently refused a negative would make the cheaper option unexpressible.
  it "accepts a negative price delta, because taking something away is a choice" do
    option = create(:catalog_item_option, catalog_item: item, name: "Rice")

    post "/admin/catalog_item_option_values", params: {
      catalog_item_option_value: {
        catalog_item_option_id: option.id, name: "No rice", price_delta: "-20",
        is_available: true, position: 2
      }
    }

    expect(CatalogItemOptionValue.order(:id).last.price_delta).to eq(-20)
  end

  # Same reason as the item's own form: `currency` defaults to AFN, and an
  # operator typing one is the front door to the mixed-currency total CLAUDE.md
  # records as already shipped once in another app.
  it "does not let an operator type a currency on a price delta" do
    expect(CatalogItemOptionValueDashboard::FORM_ATTRIBUTES).not_to include(:currency)
    expect(CatalogItemOptionValueDashboard::FORM_ATTRIBUTES).to include(:name, :price_delta, :is_available)
  end

  # An operator building a menu is already on the dish's page; making them find
  # a separate list to add "Size" is the affordance failure the undo button had.
  it "shows a dish's options on the dish's own page" do
    create(:catalog_item_option, catalog_item: item, name: "Spice")

    get "/admin/catalog_items/#{item.id}"

    expect(response.body).to match(/spice/i),
                             "an operator cannot see a dish's options from the dish"
  end
end
