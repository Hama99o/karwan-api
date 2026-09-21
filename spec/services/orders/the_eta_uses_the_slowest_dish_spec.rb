require "rails_helper"

# ── TWO NUMBERS FOR ONE DISH, AND THE PROMISE WAS THE OPTIMISTIC ONE ───────
#
# `CatalogItem#effective_prep_time_minutes` — the item's own time, else the
# merchant's — is already served to a browsing customer. `ArrivalWindow`
# computed its kitchen leg from `merchant.effective_prep_time_minutes` ALONE,
# so a customer who read "45 minutes" on a dish was then promised a window
# built from the shop's default of 20.
RSpec.describe "the arrival window uses the slowest dish in the order" do
  let(:merchant) { create(:merchant, prep_time_minutes: 20, latitude: 34.5553, longitude: 69.2075) }
  let(:customer) { create(:user, :customer) }

  def place(item_prep_times)
    lines = item_prep_times.map do |minutes|
      item = create(:catalog_item, merchant: merchant, price: 400, prep_time_minutes: minutes)
      { catalog_item_id: item.id, quantity: 1 }
    end

    Orders::PlaceService.new(
      customer: customer, merchant: merchant, lines: lines,
      delivery_latitude: 34.5600, delivery_longitude: 69.2100,
      delivery_landmark_note: "blue gate", customer_phone: customer.phone
    ).call
  end

  it "snapshots each line's prep time at order time" do
    order = place([ 45 ])

    expect(order.order_items.first.prep_time_minutes).to eq(45)
  end

  # One-way door 1. A merchant raising a dish's prep time must not retroactively
  # change what a past customer was promised.
  it "does not follow a later change to the menu" do
    item = create(:catalog_item, merchant: merchant, price: 400, prep_time_minutes: 45)
    order = Orders::PlaceService.new(
      customer: customer, merchant: merchant,
      lines: [ { catalog_item_id: item.id, quantity: 1 } ],
      delivery_latitude: 34.5600, delivery_longitude: 69.2100,
      delivery_landmark_note: "blue gate", customer_phone: customer.phone
    ).call

    item.update!(prep_time_minutes: 5)

    expect(order.order_items.first.reload.prep_time_minutes).to eq(45)
  end

  # ── THE WINDOW ITSELF MOVES, WHICH IS THE POINT ────────────────────────
  it "promises a later window for a slower dish" do
    quick = place([ 10 ])
    slow = place([ 90 ])

    quick_window = Orders::ArrivalWindow.for(quick)
    slow_window = Orders::ArrivalWindow.for(slow)

    expect(quick_window).to be_present, "no window to compare, so this proves nothing"
    expect(slow_window.to).to be > quick_window.to,
                              "the 90-minute dish is promised no later than the 10-minute one"
  end

  # A kitchen cooks the order together and is finished when the slowest dish is
  # finished. Summing would promise two hours for three kebabs.
  it "takes the slowest dish and not the sum" do
    order = place([ 20, 45, 30 ])

    one_slow = place([ 45 ])

    expect(Orders::ArrivalWindow.for(order).to).to eq(Orders::ArrivalWindow.for(one_slow).to),
                                                    "three dishes were added up instead of cooked together"
  end

  # A FALLBACK, NOT A FLOOR: the snapshot already resolves item-or-merchant per
  # line, so a dish the kitchen marked faster than its own default must keep it.
  it "keeps a dish that is quicker than the shop's default" do
    order = place([ 5 ])

    expect(order.order_items.first.prep_time_minutes).to eq(5)
    expect(Orders::ArrivalWindow.for(order).to).to be < Orders::ArrivalWindow.for(place([ 20 ])).to
  end

  # An order placed before the column existed, or one of unprepared goods.
  it "falls back to the shop's time when no line carries one" do
    order = place([ 30 ])
    order.order_items.update_all(prep_time_minutes: nil)

    expect { Orders::ArrivalWindow.for(order.reload) }.not_to raise_error
    expect(Orders::ArrivalWindow.for(order)).to be_present
  end
end
