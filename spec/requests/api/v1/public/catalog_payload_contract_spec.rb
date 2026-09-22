require "rails_helper"

# ═══ THE CATALOG: EVERY ORDERABILITY STATE, AND A QUERY COUNT THAT HOLDS ═══
#
# The first screen a user talked into installing this app ever sees, and the
# only one they reach before being asked for anything (correction 10). It is
# also the busiest endpoint in the API and the only heavy one that is public and
# unauthenticated.
#
# ── WHY THE PAYLOAD IS CAPTURED ───────────────────────────────────────────
#
# `is_available` and `unorderable` are two fields that can disagree, and the
# disagreement is CORRECT — which is exactly what prose cannot convey and a
# committed response can. All four states sit in one file, in one response:
#
#   Chicken Kabab   available true   unorderable null                          orderable
#   Lamb Kabab      available false  unorderable "sold_out"                    the merchant's toggle
#   Mixed Grill     available TRUE   unorderable "required_option_unavailable" ← the trap
#   Qabuli Palaw    available true   unorderable null, one value filtered out  orderable, quietly thinner
#
# **Mixed Grill is the row that matters.** `is_available` is the merchant's
# sold-out toggle and says `true`; the required "Size" has no available values,
# so no valid line can be built from it. A client greying on `!is_available` —
# the older, more obvious field — offers a dish the cart will refuse with
# *"Size requires at least 1"*, naming a choice the customer was never shown.
#
# ── AND WHY THERE IS A QUERY-COUNT EXAMPLE IN A PAYLOAD SPEC ──────────────
#
# Because the cost of this payload is not in its bytes. MEASURED: it was eight
# queries per category, growing linearly — 30 for three categories, 54 for six.
# `CatalogCategory#items_for_serialization` issued its own query per category
# while the controller ALSO declared an `includes` that was thrown away, because
# calling `catalog_items.…` on the association builds a fresh relation and
# ignores what was loaded. Its comment said it existed to prevent an N+1, and it
# did — the inner one.
RSpec.describe "the public catalog contract", type: :request do
  let(:merchant) { create(:merchant, name: "کباب شهر نو") }

  def fixture
    JSON.parse(Rails.root.join("spec/fixtures/files/public_catalog_orderability.json").read)
  end

  # Ids are database-assigned and a Postgres sequence does not roll back with
  # the transaction, so they are renumbered in the order served — the ORDER is
  # the contract and the values are not. See `docs/TESTING.md`.
  def catalog_payload
    get "/api/v1/public/merchants/#{merchant.id}/catalog"
    expect(response).to have_http_status(:ok), "not the catalog at all: #{response.body[0, 160]}"
    body = JSON.parse(response.body)
    body["catalogs"].each_with_index do |category, ci|
      category["id"] = ci + 1
      category["items"].each_with_index do |item, ii|
        item["id"] = ii + 1
        item["options"].each_with_index do |option, oi|
          option["id"] = oi + 1
          option["values"].each_with_index { |value, vi| value["id"] = vi + 1 }
        end
      end
    end
    body
  end

  def build_every_orderability_state!
    category = create(:catalog_category, merchant: merchant, name: "کباب", position: 0)

    create(:catalog_item, catalog_category: category, name: "Chicken Kabab", position: 0)
    create(:catalog_item, catalog_category: category, name: "Lamb Kabab", is_available: false, position: 1)

    # AVAILABLE, and not orderable: the required choice has nothing left in it.
    blocked = create(:catalog_item, catalog_category: category, name: "Mixed Grill", position: 2)
    size = create(:catalog_item_option, catalog_item: blocked, name: "Size",
                                        required: true, min_selections: 1, position: 0)
    create(:catalog_item_option_value, catalog_item_option: size, name: "Large",
                                       is_available: false, position: 0)
    create(:catalog_item_option_value, catalog_item_option: size, name: "Small",
                                       is_available: false, price_delta: 0, position: 1)

    # Orderable, with an OPTIONAL extra partly sold out. Values are filtered
    # rather than marked — you do not grey out a size, you stop offering it.
    partly = create(:catalog_item, catalog_category: category, name: "Qabuli Palaw",
                                   price: 350, position: 3)
    extras = create(:catalog_item_option, :multiple, catalog_item: partly, name: "Extras",
                                                     required: false, min_selections: 0, position: 0)
    create(:catalog_item_option_value, catalog_item_option: extras, name: "Salad",
                                       price_delta: 50, position: 0)
    create(:catalog_item_option_value, catalog_item_option: extras, name: "Raisins",
                                       price_delta: 30, is_available: false, position: 1)
    category
  end

  def items_by_name
    catalog_payload["catalogs"].flat_map { |c| c["items"] }.index_by { |item| item["name"] }
  end

  it "matches the captured catalog, field for field" do
    build_every_orderability_state!

    expect(catalog_payload).to eq(fixture),
                               "the catalog payload changed. If deliberate, regenerate " \
                               "spec/fixtures/files/public_catalog_orderability.json and tell the mobile " \
                               "session — this is the first screen anybody sees."
  end

  # ── 1 · THE ROW WHERE THE TWO FIELDS DISAGREE, CORRECTLY ─────────────────
  it "marks a dish unorderable while its own availability flag still says true" do
    build_every_orderability_state!
    items = items_by_name

    expect(items["Mixed Grill"]["is_available"]).to be(true)
    expect(items["Mixed Grill"]["unorderable"]).to eq("required_option_unavailable"),
                                                   "a client greying on !is_available offers a dish the cart will refuse"
    expect(items["Mixed Grill"]["options"].first["minimum_required"]).to eq(1)
    expect(items["Mixed Grill"]["options"].first["values"]).to be_empty,
                                                              "the empty list is the whole reason the flag is not enough"
  end

  # ── 2 · SOLD OUT IS STILL ON THE MENU ────────────────────────────────────
  it "keeps a sold-out dish in the payload rather than removing it" do
    build_every_orderability_state!
    items = items_by_name

    expect(items).to have_key("Lamb Kabab"), "removing it reads as 'this shop no longer sells it'"
    expect(items["Lamb Kabab"]["unorderable"]).to eq("sold_out")
    expect(items["Chicken Kabab"]["unorderable"]).to be_nil
  end

  # ── 3 · A THINNER OPTION IS NOT AN UNORDERABLE DISH ──────────────────────
  it "filters a sold-out value without condemning the dish" do
    build_every_orderability_state!
    extras = items_by_name["Qabuli Palaw"]["options"].first

    expect(extras["values"].map { |v| v["name"] }).to eq(%w[Salad]),
                                                     "you do not grey out a size, you stop offering it"
    expect(items_by_name["Qabuli Palaw"]["unorderable"]).to be_nil,
                                                           "the option is optional, so losing a value costs nothing"
  end

  # ── 4 · A DISCARDED DISH IS GONE, WHICH THE IN-MEMORY FILTER MUST ALSO DO ─
  #
  # The preload made `items_for_serialization` filter in Ruby rather than in
  # SQL. Soft delete is one-way door 6, so the two branches must agree.
  it "never serves a discarded dish, preloaded or not" do
    category = build_every_orderability_state!
    category.catalog_items.find_by(name: "Chicken Kabab").discard!

    expect(items_by_name.keys).not_to include("Chicken Kabab")
    expect(category.reload.items_for_serialization.map(&:name)).not_to include("Chicken Kabab")
  end

  # ── 5 · THE COST OF THE SCREEN, WHICH IS NOT IN ITS BYTES ────────────────
  #
  # A count, not a threshold: what matters is that it does not GROW with the
  # catalog. Six categories used to cost nearly twice what three did.
  it "costs the same number of queries whatever the catalogue's size" do
    3.times do |c|
      category = create(:catalog_category, merchant: merchant, position: c)
      2.times { |i| create(:catalog_item, catalog_category: category, position: i) }
    end
    small = count_queries { get "/api/v1/public/merchants/#{merchant.id}/catalog" }

    3.upto(8) do |c|
      category = create(:catalog_category, merchant: merchant, position: c)
      2.times { |i| create(:catalog_item, catalog_category: category, position: i) }
    end
    large = count_queries { get "/api/v1/public/merchants/#{merchant.id}/catalog" }

    expect(large).to eq(small),
                     "the catalog costs #{large} queries at nine categories and #{small} at three — " \
                     "it is N+1 per category, on the busiest and only public heavy endpoint"
  end

  def count_queries
    queries = []
    subscription = ActiveSupport::Notifications.subscribe("sql.active_record") do |_, _, _, _, payload|
      queries << payload[:sql] unless payload[:name].to_s.match?(/SCHEMA|TRANSACTION/)
    end
    yield
    queries.size
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription)
  end
end
