require "rails_helper"

# ═══ THE CATALOG ADVERTISED A DISH THE CART REFUSES ════════════════════════
#
# `is_available` is the merchant's sold-out toggle — a stored fact somebody
# tapped. It is NOT the same question as "can a customer build a valid line from
# this right now", and the two came apart.
#
# Measured before this existed: a required "Size" whose values are all sold out
# serialises as
#
#     is_available: true, minimum_required: 1, values: []
#
# and `Orders::CartResolver` then answers **"Size requires at least 1"** — an
# error naming a choice the customer was never offered.
#
# The values being FILTERED rather than marked is right and is what causes it:
# you do not grey out a size, you stop offering it. The item's own flag is what
# goes on saying something no longer true.
RSpec.describe "an item says when it cannot be ordered" do
  let(:merchant) { create(:merchant) }
  let(:category) { create(:catalog_category, merchant: merchant) }
  let(:item) { create(:catalog_item, catalog_category: category, name: "Kabab", price: 400) }

  def required_size(available:)
    option = create(:catalog_item_option, catalog_item: item, name: "Size",
                                          required: true, min_selections: 1)
    create(:catalog_item_option_value, catalog_item_option: option, name: "Small", is_available: available)
    option
  end

  it "says nothing about a dish that can be ordered" do
    required_size(available: true)

    expect(item.reload.unorderable_reason).to be_nil
  end

  it "names the merchant's own toggle" do
    item.update!(is_available: false)

    expect(item.reload.unorderable_reason).to eq("sold_out")
  end

  # THE ONE THAT WAS INVISIBLE. The toggle is on, the dish reads as available,
  # and there is no size left to choose.
  it "names a required option with nothing left in it" do
    required_size(available: false)

    expect(item.reload.is_available?).to be(true), "plant a dish the merchant has NOT switched off"
    expect(item.reload.unorderable_reason).to eq("required_option_unavailable")
  end

  # `minimum_required` rather than the raw `required` flag — an option demanding
  # two choices with one value left is just as unorderable as a required one
  # with none, and only the derived figure sees that.
  it "counts how many choices the option demands, not merely that it has one" do
    option = create(:catalog_item_option, catalog_item: item, name: "Extras",
                                          required: false, min_selections: 2)
    create(:catalog_item_option_value, catalog_item_option: option, name: "Cheese", is_available: true)
    create(:catalog_item_option_value, catalog_item_option: option, name: "Chilli", is_available: false)

    expect(item.reload.unorderable_reason).to eq("required_option_unavailable")
  end

  # An OPTIONAL option running dry is not a problem — nobody has to pick one.
  it "ignores an optional option with nothing left" do
    option = create(:catalog_item_option, catalog_item: item, name: "Extras",
                                          required: false, min_selections: 0)
    create(:catalog_item_option_value, catalog_item_option: option, name: "Cheese", is_available: false)

    expect(item.reload.unorderable_reason).to be_nil
  end

  # ── THE PAYLOAD AND THE CART MUST NOW AGREE ──────────────────────────────
  #
  # The whole point. Whatever the catalog says about a dish, the cart must do —
  # asserted by running the real resolver rather than reasoning about it.
  it "agrees with what the cart will actually do" do
    required_size(available: false)

    expect(item.reload.unorderable_reason).to be_present

    expect {
      Orders::CartResolver.new(merchant: merchant,
                               lines: [ { catalog_item_id: item.id, quantity: 1 } ]).resolve
    }.to raise_error(Orders::PlaceService::InvalidOptions),
         "the catalog now says unorderable and the cart accepts it — they have come apart the other way"
  end

  it "lets the cart through when the catalog says it is orderable" do
    option = required_size(available: true)
    value = option.values.first

    expect(item.reload.unorderable_reason).to be_nil
    expect {
      Orders::CartResolver.new(
        merchant: merchant,
        lines: [ { catalog_item_id: item.id, quantity: 1, option_value_ids: [ value.id ] } ]
      ).resolve
    }.not_to raise_error
  end
end
