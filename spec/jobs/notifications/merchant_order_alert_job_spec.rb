require "rails_helper"

RSpec.describe Notifications::MerchantOrderAlertJob do
  include ActiveJob::TestHelper

  let(:owner) { create(:user, :merchant_owner) }
  let(:merchant) { create(:merchant, owner: owner) }
  let!(:order) { create(:order, :with_items, merchant: merchant) }

  # Loud, repeating, until acknowledged. One push is not an alert — it is a
  # hope.
  it "re-enqueues itself while the order is unanswered" do
    expect { described_class.new.perform(order.id, attempt: 1) }
      .to have_enqueued_job(described_class).with(order.id, attempt: 2)
  end

  # ACKNOWLEDGEMENT IS THE MERCHANT ACTING, not dismissing a dialog: a
  # dismissed notification and a cooked meal are different things.
  it "stops once the merchant accepts" do
    order.update!(status: :accepted, accepted_at: Time.current)

    result = described_class.new.perform(order.id, attempt: 2)

    expect(result[:stopped]).to eq(:answered)
    expect(enqueued_jobs).to be_empty
  end

  it "stops once the merchant rejects" do
    order.update!(status: :rejected, rejected_at: Time.current)

    expect(described_class.new.perform(order.id, attempt: 1)[:stopped]).to eq(:answered)
  end

  it "stops if the customer cancelled first" do
    order.update!(status: :cancelled, cancelled_at: Time.current)

    expect(described_class.new.perform(order.id, attempt: 1)[:stopped]).to eq(:answered)
  end

  it "does not raise for an order that no longer exists" do
    expect(described_class.new.perform(-1)[:stopped]).to eq(:gone)
  end

  # THE THIRD CHANNEL IS A PERSON. Delivery is an operations business with an
  # app attached, so an exhausted push writes the row that puts it in front of
  # somebody rather than pretending another retry will work.
  describe "escalation" do
    it "stops after the maximum attempts and flags it for a phone call" do
      result = described_class.new.perform(order.id, attempt: described_class::MAX_ATTEMPTS)

      expect(result[:stopped]).to eq(:escalated)
      expect(enqueued_jobs).to be_empty

      log = AuditLog.where(action: "merchant.alert_unanswered", target: order).last
      expect(log).to be_present
      expect(log.details["note"]).to match(/telephone the merchant/)
    end

    # The number to ring, in the row. An operator should not have to go looking.
    it "records the numbers a human would need" do
      merchant.update!(phone: "+93780000001", contact_person_name: "Gul Mohammad",
                       contact_person_phone: "+93780000002")

      described_class.new.perform(order.id, attempt: described_class::MAX_ATTEMPTS)

      details = AuditLog.where(action: "merchant.alert_unanswered").last.details
      expect(details["merchant_phone"]).to eq("+93780000001")
      expect(details["contact_phone"]).to eq("+93780000002")
    end

    # The retry window matches the `placed` timeout: after that the order is
    # closed automatically, and ringing a merchant about it would be worse than
    # useless.
    it "gives up inside the window the order itself survives" do
      total = described_class::INTERVAL * (described_class::MAX_ATTEMPTS - 1)

      expect(total).to be <= Order::TIMEOUTS[:placed]
    end
  end

  describe "when an order is placed" do
    it "is enqueued by the placement service, so every path gets it" do
      customer = create(:user, :customer)
      category = create(:catalog_category, merchant: merchant)
      item = create(:catalog_item, catalog_category: category)

      expect {
        Orders::PlaceService.new(
          customer: customer, merchant: merchant,
          lines: [ { catalog_item_id: item.id, quantity: 1 } ],
          delivery_latitude: 34.54, delivery_longitude: 69.175
        ).call
      }.to have_enqueued_job(described_class)
    end
  end
end
