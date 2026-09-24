require "rails_helper"

# ── A PUSH CARRIES IDENTIFIERS, NOT CONTENT ─────────────────────────────────
#
# Every push transits Google's servers (and Apple's), sits in whatever store
# the OS keeps, and may land on a shared phone. So its payload says WHAT
# HAPPENED and WHICH RECORD; the app fetches the substance over its own
# authenticated channel when it opens. Set as a principle on 24 Sept 2026,
# after an operator's free-text note about an applicant ("the guarantor denied
# it") and a courier's personal number were found travelling in the clear.
#
# Each notifier is driven and its `data` keys are held to the list below. A
# new key fails until somebody argues, here, that it is an identifier.
RSpec.describe "a push carries identifiers, not content" do
  let(:client) { instance_double(Notifications::FcmClient) }
  let(:sent) { [] }
  let(:merchant) { create(:merchant, owner: create(:user, :merchant_owner), latitude: 34.5553, longitude: 69.2075) }

  before do
    allow(client).to receive(:send_to) do |_tokens, **options|
      sent << options[:data]
      Notifications::FcmClient::Result.new(delivered: 1, failed: 0, status: :ok)
    end
  end

  # key => why it is an identifier (or a code, or a figure the owner kept).
  ALLOWED_PUSH_DATA = {
    merchant_alert: {
      order_id: "the record", order_code: "the code the shop reads out", deep_link: "event + record",
      item_count: "a count, and the value the app's own words interpolate",
      merchant_payout: "a figure the owner kept on the wire deliberately (not on the lock screen); §F",
      currency: "the unit of that figure"
    },
    arrival_alert: { kind: "delivery or ride", job_id: "the record", code: "the order's code", deep_link: "event + record" },
    courier_check_in: { kind: "delivery or ride", job_id: "the record", code: "the job's code", status: "a state code",
                        deep_link: "event + record" },
    courier_review_alert: { status: "a state code", missing: "document CODES still needed, never their contents",
                            deep_link: "where to go" }
  }.freeze

  def keys_of(data) = data.keys.map(&:to_sym)

  it "sends the shop only identifiers" do
    order = create(:order, :with_items, merchant: merchant)
    create(:device_token, user: merchant.owner, token: "tablet")
    Notifications::MerchantAlert.new(order, client: client).deliver!

    expect(keys_of(sent.last) - ALLOWED_PUSH_DATA[:merchant_alert].keys).to be_empty
  end

  it "sends the customer only identifiers — no courier's number" do
    customer = create(:user, :customer)
    create(:device_token, user: customer, token: "phone")
    Notifications::ArrivalAlert.new(create(:order, :with_items, :picked_up, merchant: merchant, customer: customer),
                                    client: client).deliver!

    expect(keys_of(sent.last) - ALLOWED_PUSH_DATA[:arrival_alert].keys).to be_empty
  end

  it "sends the courier only identifiers — no phone number" do
    courier = create(:user, :courier)
    create(:device_token, user: courier, token: "courier-phone")
    job = create(:order, :with_items, :picked_up, merchant: merchant, courier: courier)
    expect(Notifications::CourierCheckIn.applies_to?(job)).to be(true)
    Notifications::CourierCheckIn.new(job, client: client).deliver!

    expect(keys_of(sent.last) - ALLOWED_PUSH_DATA[:courier_check_in].keys).to be_empty
  end

  it "sends an applicant only codes — never what an operator wrote about him" do
    profile = create(:courier_profile, :documented)
    create(:device_token, user: profile.user, token: "applicant-phone")
    profile.reject!(by: nil, reason: "ضمانت‌کننده انکار کرد")
    Notifications::CourierReviewAlert.new(profile.reload, client: client).deliver!

    expect(keys_of(sent.last) - ALLOWED_PUSH_DATA[:courier_review_alert].keys).to be_empty
  end

  it "has an entry for every notifier, so a fifth cannot arrive unchecked" do
    notifiers = Dir[Rails.root.join("app/services/notifications/*.rb")]
                  .select { |f| File.read(f).include?("@client.send_to(") }
                  .map { |f| File.basename(f, ".rb").to_sym }

    expect(notifiers).to match_array(ALLOWED_PUSH_DATA.keys)
  end
end
