require "rails_helper"

# ── R19: SALES, COMMISSION DEDUCTED, NET RECEIVED ──────────────────────────
#
# Hamma9900's words. Under Model A the answer to "how much do they owe us" is
# normally nothing — the courier pays the shop in cash at every pickup — so the
# statement is a record of what already happened rather than an invoice.
#
# R19 also states the constraint: statements are SNAPSHOT when issued, never
# recomputed, because a later change to the calculation would silently rewrite
# what somebody was shown last month.
RSpec.describe Merchants::IssueStatement do
  let(:merchant) { create(:merchant) }
  let(:period_start) { 7.days.ago.to_date }
  let(:period_end) { 1.day.ago.to_date }

  def delivered_order(at:, items: 400, commission: 50, fee: 100)
    create(:order, :with_items, :delivered, merchant: merchant,
                                            items_total: items, delivery_fee: fee,
                                            customer_total: items + fee, commission: commission,
                                            courier_fee: fee, merchant_payout: items - commission,
                                            delivered_at: at)
  end

  def issue = described_class.new(merchant, period_start: period_start, period_end: period_end).call

  it "reports sales, commission and net received" do
    delivered_order(at: 3.days.ago, items: 400, commission: 50)
    delivered_order(at: 2.days.ago, items: 600, commission: 90)

    statement = issue.first

    expect(statement.orders_count).to eq(2)
    expect(statement.items_total).to eq(1_000)
    expect(statement.commission).to eq(140)
    expect(statement.net_received).to eq(860)
  end

  # ── NET IS NOT A RESIDUAL ───────────────────────────────────────────────
  #
  # It is summed from `merchant_payout` on the orders, not computed as sales
  # minus commission. So this reconciliation is an ASSERTION about two
  # independently-sourced figures rather than arithmetic restating itself — the
  # distinction `money_conservation_spec` exists to enforce.
  it "reconciles against figures that came from different columns" do
    delivered_order(at: 3.days.ago, items: 400, commission: 50)

    statement = issue.first

    expect(statement).to be_reconciles
    expect(statement.net_received).to eq(400 - 50)
  end

  it "catches an order whose payout does NOT match its own sale and commission" do
    order = delivered_order(at: 3.days.ago, items: 400, commission: 50)
    order.update_column(:merchant_payout, 300)

    statement = issue.first

    expect(statement.net_received).to eq(300)
    expect(statement).not_to be_reconciles,
                            "a payout that disagrees with the sale went unnoticed, which is the one thing " \
                            "a statement exists to let somebody check"
  end

  # Delivered in the period, not placed in it: that is when the courier handed
  # over cash and the money actually moved.
  it "counts an order by when it was delivered" do
    delivered_order(at: 10.days.ago)
    delivered_order(at: 3.days.ago)

    expect(issue.first.orders_count).to eq(1), "an order delivered outside the period was counted"
  end

  it "ignores an order that was never delivered" do
    create(:order, :with_items, merchant: merchant)
    delivered_order(at: 3.days.ago)

    expect(issue.first.orders_count).to eq(1)
  end

  # A weekly job retried, redeployed or re-run by hand must not hand a merchant
  # two statements for one week.
  it "issues once for a period however many times it is run" do
    delivered_order(at: 3.days.ago)

    first = issue
    expect { issue }.not_to change { MerchantStatement.count }
    expect(issue.map(&:id)).to eq(first.map(&:id))
  end

  # ── SNAPSHOT, WHICH IS THE WHOLE POINT ──────────────────────────────────
  it "does not move when the orders behind it change afterwards" do
    order = delivered_order(at: 3.days.ago, items: 400, commission: 50)
    statement = issue.first

    order.update_columns(items_total: 9_999, commission: 1, merchant_payout: 9_998)

    expect(statement.reload.items_total).to eq(400),
                                            "the statement followed a later edit, so last month's figure " \
                                            "just changed under the merchant"
    expect(statement.commission).to eq(50)
  end

  it "issues nothing for a shop with no delivered orders in the period" do
    expect(issue).to be_empty
  end
end
