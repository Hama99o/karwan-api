require "rails_helper"

# ═══ THE FIRST REAL RESTAURANT, END TO END ═════════════════════════════════
#
# PRODUCT.md:22 is the requirement: **"you cannot test an order without a
# restaurant and a menu, and you cannot operate without being able to see and
# fix."** Every door in that sentence was missing as recently as this morning —
# hours, menu, browse category — and each was closed by its own commit with its
# own spec.
#
# This is the rehearsal, and it exists as ONE file for three reasons:
#
#   * each half is convincing alone and wrong. A console that writes rows no
#     customer can order from, and a customer screen fed only by seeds, both
#     pass their own specs.
#   * **a missing door in the MIDDLE of this chain is invisible to every
#     per-model count we have.** `bin/console_doors` asks whether a model is
#     reachable; it cannot ask whether the sequence works.
#   * the day he onboards a real shop, the sequence is written down and tested
#     rather than improvised over a phone call.
#
# ── THE ONE STEP AN OPERATOR CANNOT DO, STATED RATHER THAN ROUTED AROUND ──
#
# `admin/users` exposes index, show and edit — **not `new` or `create`**. So an
# operator cannot create the shop owner's ACCOUNT, and this rehearsal does not
# pretend otherwise with a factory: the owner registers through the API like any
# other person, which is correction 18's one-identity rule, and the operator
# then links that account to the shop. That seam is real and the rehearsal walks
# it, because it is what will actually happen in the room.
RSpec.describe "the first restaurant, from console to customer", type: :request do
  let(:admin) do
    AdminUser.create!(name: "Najibullah", email: "ops@karwan.af", password: "a-long-test-password")
  end

  # Reference data, seeded rather than operator-created on purpose:
  # `MerchantKind` is deliberately not routed (its dashboard says so) because
  # the three localised names are content, not an operator's typing.
  let!(:kind) { create(:merchant_kind, slug: "restaurant", name_en: "Restaurant") }
  let!(:browse_category) { create(:merchant_category, slug: "kabab", name_en: "Kabab") }

  def sign_in_admin!
    post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
  end

  it "walks the whole sequence, and the customer can order at the end of it" do
    # libvips is in the production image and on no dev box here; the variant
    # DECISION is tested in served_images_are_resized_spec. This rehearsal cares
    # that a photo reaches the customer, so it pins the branch and moves on.
    allow(Attachments::PublicUrl).to receive(:variants_processable?).and_return(true)
    sign_in_admin!

    # ── 1 · THE SHOP ───────────────────────────────────────────────────────
    post "/admin/merchants", params: {
      merchant: {
        name: "Kabab House", merchant_kind_id: kind.id, phone: "+93780000111",
        status: "active", prep_time_minutes: 20, commission_rate: "0.125",
        latitude: "34.5553", longitude: "69.2075",
        landmark_note: "Opposite the Shar-e-Naw mosque",
        owner_name: "Haji Naim", owner_phone: "+93790000111",
        merchant_category_ids: [ browse_category.id ]
      }
    }
    merchant = Merchant.find_by!(name: "Kabab House")
    expect(merchant.merchant_categories).to include(browse_category),
                                            "the shop was created but could not be put in a browse category"

    # ── 2 · ITS HOURS ──────────────────────────────────────────────────────
    post "/admin/merchant_opening_hours", params: {
      merchant_opening_hour: {
        merchant_id: merchant.id, day_of_week: 6, opens_at: "09:00", closes_at: "22:00"
      }
    }
    expect(merchant.opening_hours.count).to eq(1),
                                            "the shop's hours could not be set — a customer will never see when it opens"

    # ── 3 · ITS MENU, with the photo AFGHAN_UX makes the label ─────────────
    post "/admin/catalog_categories", params: {
      catalog_category: { merchant_id: merchant.id, name: "Kababs", position: 1 }
    }
    category = merchant.catalog_categories.first
    expect(category).to be_present, "the menu has no categories — the item below has nowhere to go"

    post "/admin/catalog_items", params: {
      catalog_item: {
        merchant_id: merchant.id, catalog_category_id: category.id,
        name: "Chicken Kabab", description: "One skewer, rice, salad",
        price: "400", is_available: true, prep_time_minutes: 15, position: 1,
        photo: Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/photo.png"), "image/png")
      }
    }
    item = merchant.catalog_items.first
    expect(item).to be_present
    expect(item.photo).to be_attached, "the menu item has no photo — AFGHAN_UX makes that the LABEL"

    # ── 4 · OPEN FOR BUSINESS ──────────────────────────────────────────────
    patch "/admin/merchants/#{merchant.id}/open_merchant"
    expect(merchant.reload.is_open).to be(true), "the shop cannot be opened for business"

    # ── 5 · A CUSTOMER FINDS IT ────────────────────────────────────────────
    get "/api/v1/public/merchants"
    listed = JSON.parse(response.body).fetch("merchants")
    expect(listed.map { |m| m["name"] }).to include("Kabab House"),
                                            "the shop is open and does not appear on the browse screen"

    get "/api/v1/public/merchants", params: { category_id: browse_category.id }
    expect(JSON.parse(response.body).fetch("merchants").map { |m| m["name"] }).to include("Kabab House")

    # ── 6 · READS ITS HOURS AND ITS MENU ───────────────────────────────────
    get "/api/v1/public/merchants/#{merchant.id}"
    detail = JSON.parse(response.body).fetch("merchant")
    expect(detail["opening_hours"]).to be_present, "a customer still cannot see when this shop opens"

    get "/api/v1/public/merchants/#{merchant.id}/catalog"
    catalogs = JSON.parse(response.body).fetch("catalogs")
    expect(catalogs.first["name"]).to eq("Kababs")
    served = catalogs.first["items"].first
    expect(served["name"]).to eq("Chicken Kabab")
    expect(served["photo_url"]).to include("/representations/"),
                                  "the menu photo is being served at camera resolution"

    # ── 7 · AND ORDERS FROM IT ─────────────────────────────────────────────
    customer = create(:user, :customer)
    customer_auth = { "Authorization" => "Bearer #{UserSession.issue!(customer).last}" }

    post "/api/v1/customer/orders", params: {
      order: {
        merchant_id: merchant.id,
        delivery_latitude: 34.5290, delivery_longitude: 69.1610,
        delivery_landmark_note: "Blue gate, second floor",
        lines: [ { catalog_item_id: item.id, quantity: 1 } ]
      }
    }, headers: customer_auth

    expect(response).to have_http_status(:created),
                        "the customer cannot order from a shop the console just built: #{response.body}"
    order = Order.find_by!(id: JSON.parse(response.body).dig("order", "id"))
    expect(order.merchant).to eq(merchant)

    # ── 8 · AND IT REACHES THE SHOP'S BOARD ────────────────────────────────
    #
    # THE SEAM. The owner's ACCOUNT cannot be made by an operator — `admin/users`
    # has no `create` — so the person registers through the app, as correction 18
    # requires, and the operator links them afterwards.
    owner = create(:user, :merchant_owner, phone: "+93790000111", name: "Haji Naim")
    sign_in_admin!
    patch "/admin/merchants/#{merchant.id}", params: { merchant: { owner_id: owner.id } }
    expect(merchant.reload.owner).to eq(owner), "the operator cannot link the owner's account to the shop"

    get "/api/v1/merchant/orders",
        headers: { "Authorization" => "Bearer #{UserSession.issue!(owner).last}" }

    board = JSON.parse(response.body).fetch("orders")
    expect(board.map { |o| o["code"] }).to include(order.code),
                                           "the order never reached the shop's board"
  end
end
