require "rails_helper"

RSpec.describe WalletEntry, type: :model do
  describe "validations" do
    it { is_expected.to belong_to(:courier_wallet) }
    it { is_expected.to belong_to(:source).optional }
    it { is_expected.to belong_to(:recorded_by).optional }

    it "requires a currency it recognises" do
      expect(build(:wallet_entry, currency: "USD")).not_to be_valid
    end
  end

  describe "signed amounts" do
    # Under Model A (cash) the courier holds the money and OWES us commission,
    # so the balance counts down. Under online payment WE hold the money and OWE
    # the courier their fee, so it counts up. There is deliberately no
    # non-negative constraint on either side — these examples exist to stop one
    # being added in good faith.
    it "accepts a debit" do
      expect(build(:wallet_entry, :commission, amount: -50)).to be_valid
    end

    it "accepts a credit" do
      expect(build(:wallet_entry, amount: 1_000)).to be_valid
    end

    it "accepts a negative balance_after" do
      expect(build(:wallet_entry, amount: -50, balance_after: -450)).to be_valid
    end
  end

  describe "kinds" do
    # Each of these is a real policy in CLAUDE.md, not a taxonomy for its own
    # sake: commission is what we take, top_up is a bank deposit reconciled by
    # the 4-digit code, reimbursement is the platform absorbing a refused order
    # the same day, adjustment is a named human fixing something, and
    # commission_topup is US GIVING BACK — the distance top-up on a thin far
    # order, which is the opposite direction from `top_up` despite the name.
    it "covers the five ways money moves" do
      expect(described_class.kinds.keys)
        .to eq(%w[commission top_up reimbursement adjustment commission_topup])
    end

    # THE INTEGERS ARE THE CONTRACT, not the order of the keys. They are in the
    # database, so appending is safe and renumbering would silently rewrite
    # history — every commission becoming a top-up. Asserted as the mapping
    # rather than as a list, because a list only catches a REORDER and this
    # catches a renumber too.
    it "never renumbers, because the integers are already in the database" do
      expect(described_class.kinds).to eq(
        "commission" => 0, "top_up" => 1, "reimbursement" => 2,
        "adjustment" => 3, "commission_topup" => 4
      )
    end
  end

  describe ".totals_by_currency" do
    # NEVER sum across currencies. edu-safi shipped a total that added afghanis
    # to dollars; this groups instead, so a second currency can only ever
    # produce a second group, never a wrong number.
    it "groups rather than summing" do
      wallet = create(:courier_wallet, balance: 0)
      wallet.record_entry!(kind: :top_up, amount: 1_000)
      wallet.record_entry!(kind: :commission, amount: -50)

      expect(described_class.totals_by_currency).to eq({ "AFN" => 950 })
    end

    it "returns one entry per currency, never a combined figure" do
      wallet = create(:courier_wallet, balance: 0)
      wallet.record_entry!(kind: :top_up, amount: 1_000)

      expect(described_class.totals_by_currency.keys).to eq([ "AFN" ])
    end
  end

  describe "provenance across both demand types" do
    let(:wallet) { create(:courier_wallet, balance: 1_000) }

    it "links to an order" do
      order = create(:order)
      entry = wallet.record_entry!(kind: :commission, amount: -50, source: order)

      expect(entry.source).to eq(order)
      expect(entry.source_type).to eq("Order")
    end

    it "links to a trip" do
      trip = create(:trip)
      entry = wallet.record_entry!(kind: :commission, amount: -19.38, source: trip)

      expect(entry.source).to eq(trip)
      expect(entry.source_type).to eq("Trip")
    end

    it "allows no source at all, for a top-up that belongs to no job" do
      entry = wallet.record_entry!(kind: :top_up, amount: 500)

      expect(entry.source).to be_nil
      expect(entry).to be_valid
    end

    # The trade-off of a polymorphic reference: there is no database foreign
    # key, so an orphan is possible. It is acceptable ONLY because the row is
    # self-contained — it carries its own amount, currency and balance_after,
    # so a lost source degrades to "an entry whose job is unknown" rather than
    # to wrong money. This pins that property.
    it "survives its job being destroyed, with the money intact" do
      order = create(:order)
      entry = wallet.record_entry!(kind: :commission, amount: -50, source: order)

      order.destroy

      expect(entry.reload.amount).to eq(-50)
      expect(entry.balance_after).to eq(950)
      expect(entry.source).to be_nil
    end
  end

  describe "as an append-only ledger" do
    # One-way door #4: a balance can always be recomputed from entries; entries
    # can never be reconstructed from a balance.
    it "has no updated_at" do
      # by-design: a column list is never empty, and the next line asserts created_at IS present.
      expect(described_class.column_names).not_to include("updated_at")
      expect(described_class.column_names).to include("created_at")
    end

    it "records who recorded it, because a money row with no author is unauditable" do
      admin = create(:user, :admin)
      wallet = create(:courier_wallet, balance: 0)

      entry = wallet.record_entry!(kind: :top_up, amount: 500, recorded_by: admin)

      expect(entry.recorded_by).to eq(admin)
    end

    it "reads back as a statement without replaying the ledger" do
      wallet = create(:courier_wallet, balance: 0)
      wallet.record_entry!(kind: :top_up, amount: 1_000)
      wallet.record_entry!(kind: :commission, amount: -50)
      wallet.record_entry!(kind: :reimbursement, amount: 400)

      statement = wallet.wallet_entries.chronological.map { |e| [ e.kind, e.amount, e.balance_after ] }

      expect(statement).to eq([
        [ "top_up", 1_000, 1_000 ],
        [ "commission", -50, 950 ],
        [ "reimbursement", 400, 1_350 ]
      ])
    end
  end

  describe ".newest_first" do
    it "puts the most recent entry at the top, which is what a wallet screen shows" do
      wallet = create(:courier_wallet, balance: 0)
      old = create(:wallet_entry, courier_wallet: wallet, created_at: 2.days.ago)
      recent = create(:wallet_entry, courier_wallet: wallet, created_at: 1.hour.ago)

      expect(wallet.wallet_entries.newest_first).to eq([ recent, old ])
    end
  end
end
