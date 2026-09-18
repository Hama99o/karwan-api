require "rails_helper"

# ═══ A FILTER NOBODY COULD FEED ════════════════════════════════════════════
#
# `public/merchants_controller:15` lets a customer filter the browse screen by
# `category_id`, and until 2026-09-18 **nothing could assign a merchant to a
# category** — no dashboard, no route, no field on the merchant's page. A read
# path whose write path did not exist, and LIVE rather than latent, because the
# filter was already on the customer's screen.
#
# The same shape as the opening hours, found by the same sweep, and the pair is
# the argument for the sweep: neither was a bug anybody could see from the API.
RSpec.describe "assigning a merchant to a browse category", type: :request do
  let(:admin) do
    AdminUser.create!(name: "Najibullah", email: "ops@karwan.af", password: "a-long-test-password")
  end

  before do
    post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
  end

  let!(:kabab) { create(:merchant_category, slug: "kabab", name_en: "Kabab") }
  let!(:merchant) { create(:merchant, name: "Kabab House", is_open: true) }

  it "offers a form for the taxonomy itself" do
    get "/admin/merchant_categories/new"

    expect(response).to have_http_status(:ok)
  end

  it "assigns a merchant to a category from the merchant's own page" do
    patch "/admin/merchants/#{merchant.id}", params: {
      merchant: { merchant_category_ids: [ kabab.id ] }
    }

    expect(merchant.reload.merchant_categories).to include(kabab)
  end

  # THE HALF THAT MAKES IT WORTH ANYTHING: the customer's filter now returns
  # something. Before this it returned nothing for every category, forever.
  it "makes the customer's category filter return the shop" do
    patch "/admin/merchants/#{merchant.id}", params: {
      merchant: { merchant_category_ids: [ kabab.id ] }
    }
    expect(merchant.reload.merchant_categories).to include(kabab), "not assigned — the filter below proves nothing"

    get "/api/v1/public/merchants", params: { category_id: kabab.id }

    names = JSON.parse(response.body).fetch("merchants").map { |m| m["name"] }
    expect(names).to include("Kabab House")
  end

  it "does not return a shop in a category it is not in" do
    other = create(:merchant_category, slug: "pharmacy", name_en: "Pharmacy")
    patch "/admin/merchants/#{merchant.id}", params: {
      merchant: { merchant_category_ids: [ kabab.id ] }
    }

    get "/api/v1/public/merchants", params: { category_id: other.id }

    expect(JSON.parse(response.body).fetch("merchants")).to be_empty
  end
end
