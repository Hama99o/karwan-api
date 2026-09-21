require "rails_helper"

# ═══ ONE-WAY DOOR 4 HAS A DOOR THE GATE COULD NOT SEE ══════════════════════
#
# `spec/models/money_moves_only_through_the_ledger_spec.rb` asserts that exactly
# one line in the codebase assigns a balance, inside `record_entry!`. That is a
# real gate and it holds — for ASSIGNMENTS.
#
# The ops console does not assign anything. Administrate builds its permitted
# params from a dashboard's `FORM_ATTRIBUTES` and calls `update` generically, so
# adding one symbol to an array — `%i[credit_line balance]` — lets an operator
# type a new balance into a form and move money **with no ledger row**. There is
# no `balance =` anywhere for the existing gate to find.
#
# MEASURED, not reasoned: with that symbol added, the ledger gate passed and so
# did all 1,021 examples in `spec/requests/admin` and `spec/models`. Nothing in
# the repo saw it.
#
# `CLAUDE.md`: *"Every money movement as a ledger entry, written at the moment it
# happens. A balance can always be recomputed from entries; entries can never be
# reconstructed from a balance."* A balance typed into a form is a hole in the
# books that cannot be reconstructed, and the console is the one surface with a
# human, a text field and a reason to be in a hurry.
#
# The console has PROPER ways to move money — top_up, adjust, reimburse, settle
# — each writing an entry and an audit row. This asserts the improper way stays
# shut.
RSpec.describe "a balance cannot be typed into a form", type: :request do
  let(:admin) { AdminUser.create!(name: "Ops", email: "ledger@karwan.af", password: "a-long-test-password") }
  let(:courier) { create(:user, :courier) }
  let(:wallet) { courier.courier_wallet || create(:courier_wallet, user: courier) }

  before do
    post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
    wallet.record_entry!(kind: :top_up, amount: 500, recorded_by: nil, note: "opening")
  end

  it "ignores a balance submitted to the wallet form" do
    # READ, not assumed. The first version asserted the wallet held exactly the
    # 500 this spec deposits, and the factory opens one at 1,000 — so the guard
    # fired and the real assertion never spoke. A starting balance this spec
    # does not control is fine; comparing against a number it invented is not.
    before_balance = wallet.reload.balance
    entries_before = WalletEntry.count

    expect(before_balance).to be > 0, "plant a wallet with money in it, or this proves nothing"

    patch "/admin/courier_wallets/#{wallet.id}", params: { courier_wallet: { balance: "999999", credit_line: "600" } }

    expect(wallet.reload.balance).to eq(before_balance),
                                     "an operator moved money by typing it into a form, leaving no ledger row — " \
                                     "one-way door 4, and a hole in the books cannot be reconstructed"
    expect(WalletEntry.count).to eq(entries_before)
  end

  # The legitimate field on the same form must still work, so this is a gate on
  # the balance rather than on the screen. A credit line is a permission to go
  # negative, not money that has moved, and it has no ledger entry by design.
  it "still lets the operator set the credit line" do
    patch "/admin/courier_wallets/#{wallet.id}", params: { courier_wallet: { credit_line: "600" } }

    expect(wallet.reload.credit_line).to eq(600)
  end

  # And the proper path still moves money, with a row to show for it.
  it "moves money through adjust, which writes an entry" do
    before_balance = wallet.reload.balance

    expect {
      post "/admin/courier_wallets/#{wallet.id}/adjust",
           params: { amount: "-50", note: "counted short at settlement" }
    }.to change(WalletEntry, :count).by(1)

    expect(wallet.reload.balance).to eq(before_balance - 50)
  end
end
