require "rails_helper"

# ═══ WHO MOVED THIS MONEY? ═════════════════════════════════════════════════
#
# CLAUDE.md, one-way door 5: an audit row for every intervention — "who
# credited a wallet, before and after. **Unanswerable later if nobody wrote
# it.**" And the data model names the column: `wallet_entries` carries "who
# recorded it". MONEY_AND_SETTLEMENT.md: "unexplained mismatches are theft",
# which only works if every explained one is explained in writing.
#
# ── THE INVARIANT, and it has TWO legitimate mechanisms ──────────────────
#
# A ledger movement is attributable if EITHER:
#
#   1. the entry names its author — `wallet_entries.recorded_by`, which is a
#      `User`, used by the courier-side paths; or
#   2. an audit row names the admin AND carries the `entry_id`, which is how
#      every console path does it.
#
# Both are real attribution. Asserting only the first would fail the console
# paths, which are correct; asserting only the second would fail the courier
# paths. **A gate that demanded one mechanism would be demanding a rewrite of
# whichever half it did not pick.**
#
# ── THE STRUCTURAL GAP THIS RECORDS RATHER THAN HIDES ────────────────────
#
# `wallet_entries.recorded_by_id` is a foreign key to **`users`**, and the
# console's actor is an **`AdminUser`** — a separate table, because correction
# 16 removed admin from the mobile app entirely. So an entry written by an
# operator CANNOT name its author in the ledger: wrong table, not an oversight.
#
# The information is **not lost** — it is in `audit_logs`, correlatable by
# `entry_id`. What is lost is the ledger being self-describing: a courier's
# statement, or any reconciliation built from `wallet_entries` alone, cannot say
# who made an adjustment without joining to `audit_logs`. That is a schema
# question (a second nullable FK) and it is recorded in NOTES rather than
# migrated here, because it is the money table.
RSpec.describe "every money movement is attributable", type: :request do
  let(:admin) do
    AdminUser.create!(name: "Najibullah", email: "ops@karwan.af", password: "a-long-test-password")
  end

  before do
    post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
  end

  let(:courier) { create(:user, :courier) }
  let(:wallet) { courier.courier_wallet }

  before { wallet.update!(balance: 100, credit_line: 500) }

  def attribution_for(entry)
    return { by: entry.recorded_by, how: :ledger } if entry.recorded_by_id.present?

    log = AuditLog.where(target_type: "CourierWallet", target_id: entry.courier_wallet_id)
                  .where("details->>'entry_id' = ?", entry.id.to_s)
                  .first
    log ? { by: log.admin_user, how: :audit_log } : nil
  end

  # Each console money path, driven for real. An action that moves a balance and
  # leaves nothing naming a person is the failure this exists to prevent.
  {
    "top_up" => { amount: "500", note: "bank deposit 4821" },
    "adjust" => { amount: "-50", note: "correcting a miscount" },
    "reimburse" => { amount: "400", note: "customer refused the food" }
  }.each do |action, params|
    it "names a person behind a #{action}" do
      expect {
        post "/admin/courier_wallets/#{wallet.id}/#{action}", params: params
      }.to change(WalletEntry, :count).by(1)

      entry = WalletEntry.order(:id).last
      attribution = attribution_for(entry)

      expect(attribution).to be_present,
                             "a #{action} moved #{entry.amount} and nothing records who did it — " \
                             "neither wallet_entries.recorded_by nor an audit row carrying entry_id"
      expect(attribution[:by]).to eq(admin)
    end

    it "records the balance BEFORE and after a #{action}" do
      before_balance = wallet.balance

      post "/admin/courier_wallets/#{wallet.id}/#{action}", params: params

      log = AuditLog.newest_first.first
      expect(log.before.to_s).to include(before_balance.to_i.to_s),
                                 "an `after` alone cannot answer what the balance WAS"
      expect(log.after).to be_present
    end
  end

  # The courier side uses the other mechanism, and it must keep working: these
  # entries name their author in the ledger itself.
  it "names the courier on an entry the courier's own action produced" do
    entry = wallet.record_entry!(kind: :commission, amount: -50, recorded_by: courier)

    expect(attribution_for(entry)).to include(by: courier, how: :ledger)
  end

  # A settlement moves no balance — it marks jobs settled, which clears the
  # cash-in-hand gate — so it writes no ledger row. What it must never do is
  # record a count with nobody's name against it.
  describe "a settlement" do
    it "cannot be recorded without naming who counted the cash" do
      expect {
        Settlement.create!(courier: courier, expected_amount: 50, counted_amount: 50,
                           currency: "AFN", settled_at: Time.current)
      }.to raise_error(ActiveRecord::RecordInvalid, /Counted by name/i)
    end

    it "is refused by the console too, rather than only by the model" do
      create(:order, :delivered, courier: courier, commission: 50)

      expect {
        post "/admin/courier_wallets/#{wallet.id}/settle", params: { counted_amount: "50" }
      }.not_to change(Settlement, :count)
    end
  end
end
