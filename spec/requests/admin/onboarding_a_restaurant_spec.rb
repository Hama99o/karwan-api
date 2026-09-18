require "rails_helper"

# ═══ THE FIRST REAL RESTAURANT ═════════════════════════════════════════════
#
# PRODUCT.md:22, phase 1: the console comes first because **"you cannot test an
# order without a restaurant and a menu"**. PRODUCT.md:66: **"admin onboards
# restaurants."** A shop being onboarded does not have the app yet, and the
# merchant's own screen at :78 is for MID-RUSH work — sold-out in one tap, a
# price fix — which presupposes a menu that already exists.
#
# Until 2026-09-18 the console could SEE a menu and not enter one: no admin
# routes for `CatalogCategory` or `CatalogItem`, and `FORM_ATTRIBUTES = []` on
# both. **A menu could only arrive from a seed**, so the first real restaurant
# could not be onboarded at all.
#
# This drives the whole onboarding in one file, in the order an operator would
# do it, because each step is convincing alone and the chain is what matters:
# a shop, its hours, a menu category, an item with a price and a photo — and
# then a customer seeing it.
RSpec.describe "onboarding a restaurant from the console", type: :request do
  let(:admin) do
    AdminUser.create!(name: "Najibullah", email: "ops@karwan.af", password: "a-long-test-password")
  end

  before do
    post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
  end

  let!(:merchant) { create(:merchant, name: "Kabab House", is_open: true) }

  it "offers a form for a menu category, which is what was missing" do
    get "/admin/catalog_categories/new"

    expect(response).to have_http_status(:ok)
  end

  it "creates a category and an item, and the customer can order from it" do
    expect {
      post "/admin/catalog_categories", params: {
        catalog_category: { merchant_id: merchant.id, name: "Kababs", position: 1 }
      }
    }.to change(CatalogCategory, :count).by(1)

    category = CatalogCategory.order(:id).last

    expect {
      post "/admin/catalog_items", params: {
        catalog_item: {
          merchant_id: merchant.id, catalog_category_id: category.id,
          name: "Chicken Kabab", description: "One skewer", price: "400",
          is_available: true, prep_time_minutes: 15, position: 1, size_class: "small"
        }
      }
    }.to change(CatalogItem, :count).by(1)

    # THE HALF THAT MAKES IT WORTH ANYTHING. A console that writes rows no
    # customer can order from is the dead path this replaces.
    get "/api/v1/public/merchants/#{merchant.id}/catalog"

    catalogs = JSON.parse(response.body).fetch("catalogs")
    expect(catalogs).to be_present, "the customer sees no menu for a shop that has one"
    expect(catalogs.first["name"]).to eq("Kababs")
    expect(catalogs.first["items"].map { |i| i["name"] }).to include("Chicken Kabab")
  end

  # AFGHAN_UX makes the photo the LABEL for a customer who cannot read fluently,
  # and PRODUCT.md:78 names it as part of menu management. It was not on this
  # dashboard at all, so an operator could neither see nor set one.
  it "accepts a photo, and serves it resized" do
    # libvips is in the production image and on no dev box here, so the variant
    # DECISION is pinned rather than read off the machine — both branches are
    # driven in spec/serializers/served_images_are_resized_spec.rb.
    allow(Attachments::PublicUrl).to receive(:variants_processable?).and_return(true)
    category = create(:catalog_category, merchant: merchant)

    post "/admin/catalog_items", params: {
      catalog_item: {
        merchant_id: merchant.id, catalog_category_id: category.id,
        name: "Bolani", price: "120", is_available: true, position: 1,
        photo: Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/photo.png"), "image/png")
      }
    }

    item = CatalogItem.order(:id).last
    expect(item.photo).to be_attached

    get "/api/v1/public/merchants/#{merchant.id}/catalog"
    url = JSON.parse(response.body).dig("catalogs", 0, "items", 0, "photo_url")
    expect(url).to include("/representations/"),
                   "the menu photo is being served at camera resolution"
  end

  it "corrects a price, which is the thing an operator is rung about" do
    item = create(:catalog_item, catalog_category: create(:catalog_category, merchant: merchant), price: 400)

    patch "/admin/catalog_items/#{item.id}", params: { catalog_item: { price: "450" } }

    expect(item.reload.price).to eq(450)
  end

  # ── WHAT THE FORM MUST NOT LET THROUGH ───────────────────────────────────
  #
  # The wallet's lesson: what an operator must fix is editable, and what must
  # not be bypassed is not.
  describe "the fields it deliberately does not offer" do
    # CLAUDE.md records a mixed-currency total as already shipped once in
    # another app. An operator typing a currency is that bug's front door.
    it "does not let an operator type a currency" do
      expect(CatalogItemDashboard::FORM_ATTRIBUTES).not_to include(:currency)
    end

    # Soft delete is an action, not a date. Typing it would bypass
    # `discard_dependents!` and leave a category hidden with its items visible.
    it "does not let an operator type a deletion date" do
      expect(CatalogItemDashboard::FORM_ATTRIBUTES).not_to include(:deleted_at)
      expect(CatalogCategoryDashboard::FORM_ATTRIBUTES).not_to include(:deleted_at)
    end

    # And the paired positive: the fields PRODUCT.md:78 names ARE editable, or
    # the two examples above are just a list of things we left out.
    it "offers every field menu management actually needs" do
      expect(CatalogItemDashboard::FORM_ATTRIBUTES)
        .to include(:name, :price, :photo, :prep_time_minutes, :is_available, :catalog_category)
    end
  end
end
