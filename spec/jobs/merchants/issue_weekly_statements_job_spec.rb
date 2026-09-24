require "rails_helper"

RSpec.describe Merchants::IssueWeeklyStatementsJob do
  let(:merchant) { create(:merchant) }

  def delivered_order(at:, merchant_for: merchant, items: 400, commission: 50)
    create(:order, :with_items, :delivered, merchant: merchant_for,
                                            items_total: items, delivery_fee: 100,
                                            customer_total: items + 100, commission: commission,
                                            courier_fee: 100, merchant_payout: items - commission,
                                            delivered_at: at)
  end

  # ── A FIXED WEEK, NOT A ROLLING SEVEN DAYS ──────────────────────────────
  #
  # Written first as "yesterday minus six", which slides: run daily, it issues a
  # DIFFERENT window every morning and hands a merchant a new overlapping
  # statement each day. "Weekly" would then be the job's name and not a property
  # of its output.
  it "cuts the period on the Afghan week, Saturday to Friday" do
    travel_to Time.zone.parse("2026-09-21 03:00:00 +0430") do   # a Monday
      delivered_order(at: Time.zone.parse("2026-09-16 12:00:00 +0430"))

      described_class.perform_now

      statement = merchant.statements.last
      expect(statement.period_start.strftime("%a %d %b")).to eq("Sat 12 Sep")
      expect(statement.period_end.strftime("%a %d %b")).to eq("Fri 18 Sep")
    end
  end

  it "issues for every live shop, not only the one that was asked about" do
    other = create(:merchant)
    travel_to Time.zone.parse("2026-09-21 03:00:00 +0430") do
      delivered_order(at: Time.zone.parse("2026-09-16 12:00:00 +0430"))
      delivered_order(at: Time.zone.parse("2026-09-17 12:00:00 +0430"), merchant_for: other)

      expect { described_class.perform_now }.to change { MerchantStatement.count }.by(2)
    end
  end

  # A daily schedule re-issues the same completed week, so this must be a no-op
  # rather than a second statement — otherwise a missed morning is not free.
  it "writes nothing on a second run for the same week" do
    travel_to Time.zone.parse("2026-09-21 03:00:00 +0430") do
      delivered_order(at: Time.zone.parse("2026-09-16 12:00:00 +0430"))
      described_class.perform_now

      expect { described_class.perform_now }.not_to change { MerchantStatement.count }
    end
  end

  # A statement records what happened in the week; the shop's state on the
  # morning it is cut does not undo that. Measured 24 Sept 2026: a shop
  # suspended or removed before the run got no statement, ever, for a week
  # it had delivered in.
  { "suspended" => ->(shop) { shop.update!(status: :suspended) },
    "removed" => ->(shop) { shop.discard! } }.each do |what, stop|
    it "still issues the week to a shop #{what} before the statement was cut" do
      travel_to Time.zone.parse("2026-09-21 03:00:00 +0430") do
        delivered_order(at: Time.zone.parse("2026-09-16 12:00:00 +0430"))
        stop.call(merchant)

        expect { described_class.perform_now }.to change { MerchantStatement.where(merchant: merchant).count }.by(1)
      end
    end
  end

  it "issues nothing for a week with no deliveries" do
    travel_to Time.zone.parse("2026-09-21 03:00:00 +0430") do
      expect { described_class.perform_now }.not_to change { MerchantStatement.count }
    end
  end
end
