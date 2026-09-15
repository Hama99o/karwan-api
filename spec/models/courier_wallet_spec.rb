require "rails_helper"

RSpec.describe CourierWallet, type: :model do
  describe "validations" do
    # No `validate_presence_of(:top_up_code)` matcher here: a
    # before_validation callback assigns the code, so it can never be blank and
    # the matcher would be asserting something unreachable. The examples below
    # test the behaviour that actually exists.
    it "assigns a unique 4-digit top-up code on create" do
      wallet = create(:courier_wallet)

      expect(wallet.top_up_code).to match(/\A\d{4}\z/)
    end

    it "rejects a negative credit line, which is stored as a magnitude" do
      expect(build(:courier_wallet, credit_line: -100)).not_to be_valid
    end
  end

  describe "the balance is bidirectional, by design" do
    # This matters for a change that has not happened yet, and it is cheaper to
    # prove now than to migrate later.
    #
    # Under Model A (cash, v0) the courier holds the money, so they OWE us
    # commission: the balance counts down and blocks at the floor. Under online
    # payment WE hold the money, commission is netted at source, and we OWE the
    # courier their fee: the balance counts UP. The relationship inverts, and a
    # non-negative constraint on either the balance or the entry amount would
    # have to be migrated out with live money in the table.
    #
    # So there is deliberately no such constraint. These examples exist to stop
    # someone adding one in good faith.
    it "accepts a positive balance, which is what we owe the courier" do
      wallet = build(:courier_wallet, balance: 2_500)

      expect(wallet).to be_valid
    end

    it "accepts a negative balance, which is what the courier owes us" do
      wallet = build(:courier_wallet, balance: -250)

      expect(wallet).to be_valid
    end

    it "accepts ledger entries of either sign" do
      wallet = create(:courier_wallet, balance: 0)

      debit = wallet.record_entry!(kind: :commission, amount: -50)
      credit = wallet.record_entry!(kind: :top_up, amount: 1_000)

      expect(debit.amount).to eq(-50)
      expect(credit.amount).to eq(1_000)
      expect(wallet.reload.balance).to eq(950)
    end
  end

  describe "#floor and #available_credit" do
    it "treats the credit line as how far below zero the courier may go" do
      wallet = build(:courier_wallet, balance: 200, credit_line: 500)

      expect(wallet.floor).to eq(-500)
      expect(wallet.available_credit).to eq(700)
    end
  end

  describe "#blocked?" do
    it "is false with credit remaining" do
      expect(build(:courier_wallet, balance: 100, credit_line: 500)).not_to be_blocked
    end

    # The boundary, which is the case most likely to be wrong by one. At the
    # floor exactly, work stops — this is what "at zero the app stops assigning
    # orders" means once a credit line is involved.
    it "is true exactly at the floor" do
      expect(build(:courier_wallet, :at_floor)).to be_blocked
    end

    it "is true below the floor" do
      expect(build(:courier_wallet, :below_floor)).to be_blocked
    end
  end

  describe "#can_fund?" do
    # TWO DIFFERENT GATES, one per job kind. An earlier version of this spec
    # asserted the opposite — that the payout was ignored and only the
    # commission mattered — and that was wrong. CLAUDE.md is explicit that a
    # courier is offered work "whose wallet can fund the food", and correction 7
    # makes the asymmetry a product fact.
    #
    # The consequence, which is the point: a courier too short for a delivery
    # can still take a ride.
    describe "a delivery, which the courier must advance" do
      let(:order) do
        create(:order, items_total: 400, delivery_fee: 100, customer_total: 500,
                       commission: 50, merchant_payout: 350)
      end

      it "is true when the advance fits above the floor" do
        wallet = build(:courier_wallet, balance: 0, credit_line: 500)

        expect(wallet.can_fund?(order)).to be true
      end

      it "is false when the advance would breach the floor" do
        wallet = build(:courier_wallet, balance: -200, credit_line: 500)

        expect(wallet.can_fund?(order)).to be false
      end

      # The gate is the ADVANCE, not the commission. A nearly-empty wallet must
      # not be handed a 3,950 AFN float — which the previous, wrong version of
      # this spec explicitly allowed.
      it "refuses a large order a small wallet cannot float" do
        wallet = build(:courier_wallet, balance: 0, credit_line: 100)
        big = create(:order, items_total: 4_000, delivery_fee: 100, customer_total: 4_100,
                             commission: 500, merchant_payout: 3_500)

        expect(wallet.can_fund?(big)).to be false
      end
    end

    describe "a ride, which advances nothing" do
      let(:ride) { create(:trip, fare: 155, commission: 19.38, courier_earnings: 135.62) }

      it "is fundable on a balance that could not fund a delivery" do
        wallet = build(:courier_wallet, balance: -200, credit_line: 500)
        order = create(:order, items_total: 400, delivery_fee: 100, customer_total: 500,
                               commission: 50, merchant_payout: 350)

        expect(wallet.can_fund?(order)).to be false
        expect(wallet.can_fund?(ride)).to be true
      end

      it "is refused once the wallet is blocked, like everything else" do
        expect(build(:courier_wallet, :at_floor).can_fund?(ride)).to be false
      end
    end

    it "refuses any job once the wallet is blocked" do
      wallet = build(:courier_wallet, :at_floor)

      expect(wallet.can_fund?(create(:order))).to be false
    end

    it "draws both kinds against the SAME wallet, because it is one pool" do
      courier = create(:user, :courier)
      wallet = courier.courier_wallet
      wallet.update!(balance: 1_000, credit_line: 0)

      wallet.record_entry!(kind: :commission, amount: -50, source: create(:order))
      wallet.record_entry!(kind: :commission, amount: -19.38, source: create(:trip))

      expect(wallet.reload.balance).to eq(BigDecimal("930.62"))
      expect(courier.courier_wallet.wallet_entries.count).to eq(2)
    end

    # Never compare or subtract across currencies.
    it "refuses a job in another currency rather than comparing the numbers" do
      wallet = build(:courier_wallet, balance: 10_000, currency: "AFN")
      foreign = build(:order, commission: 1)
      allow(foreign).to receive(:currency).and_return("USD")

      expect(wallet.can_fund?(foreign)).to be false
    end
  end

  describe "#record_entry!" do
    let(:wallet) { create(:courier_wallet, balance: 1_000) }
    let(:admin) { create(:user, :admin) }

    it "writes the ledger row and updates the balance together" do
      entry = wallet.record_entry!(kind: :commission, amount: -50, recorded_by: admin)

      expect(entry).to have_attributes(kind: "commission", amount: -50, balance_after: 950,
                                       recorded_by_id: admin.id, currency: "AFN")
      expect(wallet.reload.balance).to eq(950)
    end

    it "stores balance_after so a statement reads without replaying the ledger" do
      wallet.record_entry!(kind: :commission, amount: -50)
      wallet.record_entry!(kind: :top_up, amount: 500)
      wallet.record_entry!(kind: :reimbursement, amount: 400)

      expect(wallet.wallet_entries.chronological.map(&:balance_after)).to eq([ 950, 1_450, 1_850 ])
      expect(wallet.reload.balance).to eq(1_850)
    end

    it "links the entry to the job it was charged for, across both demand types" do
      order = create(:order)
      trip = create(:trip)

      order_entry = wallet.record_entry!(kind: :commission, amount: -50, source: order)
      trip_entry = wallet.record_entry!(kind: :commission, amount: -19.38, source: trip)

      expect(order_entry.source).to eq(order)
      expect(trip_entry.source).to eq(trip)
    end

    # The balance is only ever a cached sum of the ledger. If these two can
    # disagree, the wallet is not auditable.
    it "keeps the balance equal to the sum of its entries" do
      wallet.record_entry!(kind: :commission, amount: -50)
      wallet.record_entry!(kind: :top_up, amount: 1_000)
      wallet.record_entry!(kind: :adjustment, amount: -25)

      expect(wallet.reload.balance).to eq(1_000 + wallet.wallet_entries.sum(:amount))
    end

    # The balance update and the ledger row must be one atomic act. If the row
    # fails and the balance still moves, the wallet has money nobody can account
    # for — the exact condition the ledger exists to make impossible.
    #
    # Provoked with a real failure rather than a stub: `record_entry!` calls
    # `lock!` first, which reloads the record and resets the association proxy,
    # so a stub on `wallet.wallet_entries` is silently discarded before it is
    # ever reached. That is worth knowing — the earlier version of this example
    # passed nothing and looked fine.
    it "rolls back the balance if the ledger row cannot be written" do
      expect { wallet.record_entry!(kind: :not_a_real_kind, amount: 500) }
        .to raise_error(ArgumentError)
      expect(wallet.reload.balance).to eq(1_000)
      expect(wallet.wallet_entries).to be_empty
    end
  end
end
