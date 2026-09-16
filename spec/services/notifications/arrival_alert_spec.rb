require "rails_helper"

# "YOUR COURIER IS AT THE GATE."
#
# Hamma9900 asked for customer and courier to reach each other especially at
# the arrival moment, and offered a chat. A chat reaches somebody who has the
# app open; a person waiting for a delivery does not have it open — they are in
# the kitchen, on another floor, or on a phone somebody else is using
# (AFGHAN_UX.md §7). This is what reaches them, and the phone number is what
# fixes it when this does not.
RSpec.describe Notifications::ArrivalAlert do
  let(:courier) { create(:user, :courier, phone: "+93700000123") }
  let(:merchant) { create(:merchant, latitude: 34.5553, longitude: 69.2075) }
  let(:client) { instance_double(Notifications::FcmClient) }
  let(:sent) { [] }

  before do
    allow(client).to receive(:send_to) do |tokens, **options|
      sent << { tokens: tokens }.merge(options)
      Notifications::FcmClient::Result.new(delivered: tokens.size, failed: 0, status: :ok)
    end
  end

  describe "a delivery" do
    let(:booker) { create(:user, :customer, phone: "+93700000111") }
    let(:order) do
      create(:order, :picked_up, merchant: merchant, courier: courier, customer: booker,
                                 customer_phone: "+93700000222")
    end

    before { create(:device_token, user: booker, token: "device-1") }

    it "tells the person who is waiting" do
      described_class.new(order, client: client).deliver!

      expect(sent.last[:tokens]).to eq([ "device-1" ])
      expect(sent.last[:title_key]).to eq("customer.arrival.title")
    end

    # SO THEY CAN RING HIM WITHOUT OPENING ANYTHING. The number is the fallback
    # for this very notification failing, and it costs no data.
    it "carries the courier's number, because that is the fallback" do
      described_class.new(order, client: client).deliver!

      expect(sent.last[:data][:courier_phone]).to eq("+93700000123")
    end

    it "carries the code, so the notification can name the order" do
      described_class.new(order, client: client).deliver!

      expect(sent.last[:data][:code]).to eq(order.code)
      expect(sent.last[:data][:kind]).to eq("delivery")
    end

    # A Ruby class name in a payload is an implementation detail the client
    # would then depend on; the demand type is the thing it routes on.
    it "names the demand type, never the class" do
      described_class.new(order, client: client).deliver!

      expect(sent.last[:data].values.map(&:to_s)).not_to include("Order")
    end

    # ── WHO IS AT THE DOOR IS NOT WHO PAID ──────────────────────────────────
    #
    # Ordering for a relative is a primary use here. The notification goes to
    # the ACCOUNT that placed the order — that is whose device we know — while
    # the courier rings `customer_phone`, which is whoever is at that gate.
    # Two different people, and both are told by the channel that can reach
    # them.
    it "notifies the account holder while the courier rings the recipient" do
      described_class.new(order, client: client).deliver!

      expect(sent.last[:tokens]).to eq([ "device-1" ])
      expect(order.customer_phone).to eq("+93700000222")
      expect(order.customer.phone).to eq("+93700000111")
    end
  end

  describe "a ride" do
    let(:passenger) { create(:user, :customer) }
    let(:trip) { create(:trip, :arrived, passenger: passenger, courier: courier) }

    before { create(:device_token, user: passenger, token: "passenger-device") }

    it "tells the passenger" do
      described_class.new(trip, client: client).deliver!

      expect(sent.last[:tokens]).to eq([ "passenger-device" ])
      expect(sent.last[:data][:kind]).to eq("ride")
    end
  end

  describe "when it cannot be delivered" do
    let(:order) { create(:order, :picked_up, merchant: merchant, courier: courier) }

    # NOT AN ESCALATION, unlike the merchant alert: there is a human at the
    # door about to knock. Recorded so "was she told" has an answer if a
    # delivery goes wrong at the gate.
    it "records that it did not reach anybody, without escalating" do
      allow(client).to receive(:send_to)
        .and_return(Notifications::FcmClient::Result.new(delivered: 0, failed: 0, status: :no_tokens))

      expect { described_class.new(order, client: client).deliver! }
        .to change { AuditLog.for_action("arrival.announced").count }.by(1)

      log = AuditLog.for_action("arrival.announced").newest_first.first
      expect(log.details["reached"]).to be false
      expect(log.target).to eq(order)
    end
  end
end
