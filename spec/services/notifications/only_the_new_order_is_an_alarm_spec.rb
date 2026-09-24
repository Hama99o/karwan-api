require "rails_helper"

# ── ONE NOTIFICATION IS AN ALARM. THE REST ARE NOT ──────────────────────────
#
# Found 2026-09-24: every push went out on the `karwan_orders` channel with
# the alarm sound and the repeating vibration — the payload was built for the
# shop's new-order alert and every other sender inherited it. A courier's
# "you are approved" and a customer's "he is at your gate" would have sounded
# like an order to run for. Each sender is driven here, through the real
# client, and the payload that would go to Firebase is read.
RSpec.describe "only the new-order alert is an alarm" do
  let(:client) { Notifications::FcmClient.new(project_id: "karwan", access_token: "t") }
  let(:merchant) { create(:merchant, owner: create(:user, :merchant_owner), latitude: 34.5553, longitude: 69.2075) }
  let(:sent) { [] }

  before do
    stub_request(:post, %r{fcm\.googleapis\.com}).to_return do |request|
      sent << JSON.parse(request.body)["message"]
      { status: 200, body: "{}" }
    end
  end

  def android = sent.last.dig("android", "notification")

  it "sounds the kitchen alarm for a new order" do
    order = create(:order, :with_items, merchant: merchant)
    create(:device_token, user: merchant.owner, token: "tablet")

    Notifications::MerchantAlert.new(order, client: client).deliver!

    expect(android).to include("channel_id" => "karwan_orders", "sound" => "alert")
    expect(sent.last.dig("apns", "payload", "aps", "interruption-level")).to eq("time-sensitive")
  end

  it "tells a customer the courier is at the gate without the alarm" do
    customer = create(:user, :customer)
    create(:device_token, user: customer, token: "phone")
    order = create(:order, :with_items, :picked_up, merchant: merchant, customer: customer)

    Notifications::ArrivalAlert.new(order, client: client).deliver!

    expect(android).to include("channel_id" => "karwan_updates", "sound" => "default")
    expect(android).not_to have_key("vibrate_timings")
    # Still delivered at high priority: it is about something happening now.
    expect(sent.last.dig("android", "priority")).to eq("high")
  end

  it "tells an applicant the review outcome without the alarm" do
    profile = create(:courier_profile, :documented)
    create(:device_token, user: profile.user, token: "phone")
    profile.update_columns(verification_status: CourierProfile.verification_statuses[:approved])

    Notifications::CourierReviewAlert.new(profile.reload, client: client).deliver!

    expect(sent).not_to be_empty
    expect(android).to include("channel_id" => "karwan_updates")
  end
end
