require "rails_helper"

RSpec.describe Notifications::MerchantAlert do
  let(:owner) { create(:user, :merchant_owner) }
  let(:merchant) { create(:merchant, owner: owner) }
  let(:order) { create(:order, :with_items, merchant: merchant) }

  describe "with no FCM credentials, which is today" do
    # Standing up a Firebase project is Hamma9900's decision and account. The
    # distinction that matters: "nothing is configured" is a deployment state,
    # while "we could not send" must escalate to a human.
    it "reports unconfigured rather than raising" do
      owner.device_tokens.create!(token: "abc", platform: :android)

      result = described_class.new(order).deliver!

      expect(result.status).to eq(:unconfigured)
      expect(result).not_to be_configured
    end

    it "still records that the attempt happened" do
      owner.device_tokens.create!(token: "abc", platform: :android)

      described_class.new(order).deliver!

      log = AuditLog.where(action: "merchant.alerted", target: order).last
      expect(log.details["status"]).to eq("unconfigured")
      expect(log.details["needs_human_contact"]).to be true
    end
  end

  describe "with a configured client" do
    let(:client) { Notifications::FcmClient.new(project_id: "karwan", access_token: "t") }

    before do
      stub_request(:post, %r{fcm\.googleapis\.com}).to_return(status: 200, body: "{}")
    end

    it "sends to every active device the owner has registered" do
      owner.device_tokens.create!(token: "tablet", platform: :android)
      owner.device_tokens.create!(token: "phone", platform: :android)

      result = described_class.new(order, client: client).deliver!

      expect(result.delivered).to eq(2)
      expect(result.status).to eq(:ok)
    end

    # A tablet handed between staff is deactivated, not deleted. Pushing to it
    # wastes a message and, worse, reaches whoever has the old device.
    it "skips deactivated devices" do
      owner.device_tokens.create!(token: "old", platform: :android).deactivate!
      owner.device_tokens.create!(token: "current", platform: :android)

      result = described_class.new(order, client: client).deliver!

      expect(result.delivered).to eq(1)
    end

    # KEYS, not words. The server cannot write Pashto, and a server-written
    # English notification is untranslatable on the device.
    it "sends i18n keys and the values the app needs, never English text" do
      owner.device_tokens.create!(token: "tablet", platform: :android)

      described_class.new(order, client: client).deliver!

      expect(WebMock).to have_requested(:post, %r{fcm\.googleapis\.com}).with { |request|
        data = JSON.parse(request.body).dig("message", "data")
        data["title_key"] == "merchant.alert.new_order.title" &&
          data["order_code"] == order.code &&
          data["deep_link"].include?("karwan://merchant/orders/")
      }
    end

    # Cheap Android with aggressive OEM power management drops a
    # normal-priority push. A new order is not an announcement.
    it "sends at high priority with a sound, for a tablet in a noisy kitchen" do
      owner.device_tokens.create!(token: "tablet", platform: :android)

      described_class.new(order, client: client).deliver!

      expect(WebMock).to have_requested(:post, %r{fcm\.googleapis\.com}).with { |request|
        message = JSON.parse(request.body)["message"]
        message.dig("android", "priority") == "high" &&
          message.dig("android", "notification", "sound") == "alert" &&
          message.dig("apns", "headers", "apns-priority") == "10"
      }
    end

    # One dead phone must not stop the alert reaching the tablet beside it.
    it "keeps going when one device fails" do
      owner.device_tokens.create!(token: "good", platform: :android)
      owner.device_tokens.create!(token: "bad", platform: :android)
      stub_request(:post, %r{fcm\.googleapis\.com})
        .to_return({ status: 200, body: "{}" }, { status: 404, body: "{}" })

      result = described_class.new(order, client: client).deliver!

      expect(result.delivered).to eq(1)
      expect(result.failed).to eq(1)
      expect(result.status).to eq(:partial)
    end

    it "survives a network failure without raising" do
      owner.device_tokens.create!(token: "tablet", platform: :android)
      stub_request(:post, %r{fcm\.googleapis\.com}).to_timeout

      result = described_class.new(order, client: client).deliver!

      expect(result.failed).to eq(1)
      expect(result).not_to be_any_delivered
    end
  end

  # A merchant with no registered device is a recruitment problem, not a bug —
  # it should be visible in the console rather than buried in a log.
  it "flags a merchant with no device at all for human contact" do
    result = described_class.new(order).deliver!

    expect(result.status).to eq(:no_tokens)
    log = AuditLog.where(action: "merchant.alerted", target: order).last
    expect(log.details["devices"]).to eq(0)
    expect(log.details["needs_human_contact"]).to be true
  end

  it "does not raise for a merchant with no owner account yet" do
    ownerless = create(:order, merchant: create(:merchant, owner: nil))

    expect { described_class.new(ownerless).deliver! }.not_to raise_error
  end
end
