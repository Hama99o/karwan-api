require "rails_helper"

# ── THE SHOP'S NEW-ORDER PUSH CARRIES WORDS THE OS CAN DRAW ────────────────
#
# Every other push is data-only and worded by the app. This one must be
# readable with the app fully CLOSED — a blank banner on a counter is a lost
# order — so it carries a real `notification` block, rendered by the server in
# the owner's saved language (not the phone's: Karwan's language is chosen in
# the app). See config/push/merchant_new_order.yml.
RSpec.describe "the new-order push arrives in words" do
  let(:client) { Notifications::FcmClient.new(project_id: "karwan", access_token: "t") }
  let(:owner) { create(:user, :merchant_owner, locale: "fa") }
  let(:merchant) { create(:merchant, owner: owner) }
  let(:order) { create(:order, :with_items, merchant: merchant) }
  let(:sent) { [] }

  before do
    create(:device_token, user: owner, token: "tablet")
    stub_request(:post, %r{fcm\.googleapis\.com}).to_return do |request|
      sent << JSON.parse(request.body)["message"]
      { status: 200, body: "{}" }
    end
  end

  it "sends a title and body the OS can draw, in the owner's own language, filled in" do
    Notifications::MerchantAlert.new(order, client: client).deliver!

    items = order.order_items.sum(&:quantity)
    expect(sent.last["notification"]).to eq(
      "title" => "سفارش تازه #{order.code}",
      "body" => "#{items} قلم — برای پذیرفتن یا رد کردن باز کنید"
    )
  end

  it "keeps the keys and the record, so an open app can still word and route it itself" do
    Notifications::MerchantAlert.new(order, client: client).deliver!

    expect(sent.last["data"]).to include("title_key" => "merchant.alert.new_order.title",
                                         "deep_link" => "karwan://open/new-order/#{order.id}")
  end

  it "leaves every other push data-only, for the app to word" do
    customer = create(:user, :customer)
    create(:device_token, user: customer, token: "phone")
    Notifications::ArrivalAlert.new(create(:order, :with_items, :picked_up, customer: customer), client: client).deliver!

    expect(sent.last).not_to have_key("notification")
    expect(sent.last.dig("data", "deep_link")).to match(%r{\Akarwan://open/arrival/\d+\z})
  end
end
