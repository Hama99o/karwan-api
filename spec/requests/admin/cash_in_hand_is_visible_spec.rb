require "rails_helper"

# ═══ THE SECOND EXPOSURE CONTROL WAS NOT ON THE CONSOLE ════════════════════
#
# `MONEY_AND_SETTLEMENT.md` §10: *"`cash_in_hand_limit` is the second exposure
# control and is separate from the wallet: the wallet protects the goods, this
# protects cash already collected and not yet deposited."* `PRODUCT.md` asks for
# it in as many words — *"Riders — ... view cash in hand."*
#
# The console showed the BALANCE, which is what a courier owes us, and not what
# he is carrying for us. On the rig those are 2,630.62 and 69.38 on one wallet:
# a courier in good standing holding our money, and only one of the two numbers
# was on the page.
#
# ── ASSERT THE VALUE, NOT THE LABEL ───────────────────────────────────────
#
# The first version of this field was defined below `private`, so it raised.
# **Administrate served a 200 with the label present and no number**, and a
# check for "Cash in hand" passed. That is the same vacuous assertion
# `docs/NOTES.md` records from the Kabul-date fix: the row label is always
# there, and only the figure moves.
RSpec.describe "a courier's cash in hand is visible to the operator", type: :request do
  let(:admin) { AdminUser.create!(name: "Ops", email: "cash@karwan.af", password: "a-long-test-password") }
  let(:courier) { create(:user, :courier) }
  let(:wallet) { courier.courier_wallet }

  before do
    post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
  end

  # Money of OURS he is holding: commission on jobs collected and not settled.
  def collected_job(commission:)
    create(:order, :with_items, :delivered, courier: courier, commission: commission,
                                            items_total: 400, merchant_payout: 400 - commission,
                                            delivery_fee: 100, customer_total: 500, courier_fee: 100,
                                            payment_status: :collected)
  end

  def page_value(label)
    text = ActionView::Base.full_sanitizer.sanitize(response.body).gsub(/\s+/, " ")
    text[/#{Regexp.escape(label)}\s+([0-9.,-]+)/, 1]
  end

  it "is a public method, not one Administrate cannot call" do
    expect(wallet).to respond_to(:cash_in_hand)
    expect { wallet.cash_in_hand }.not_to raise_error
  end

  it "shows the number and not merely the row" do
    collected_job(commission: 50)
    collected_job(commission: 25)

    get "/admin/courier_wallets/#{wallet.id}"

    expect(response.body).to include("Cash in hand"), "the row is missing entirely"
    expect(page_value("Cash in hand")).to eq("75.00"),
                                          "the label rendered and the figure did not — Administrate serves a 200 " \
                                          "with an empty cell when the method raises"
  end

  # THE TWO NUMBERS ARE DIFFERENT QUESTIONS. A courier can owe us nothing and
  # still be carrying too much of our cash, which is why one figure cannot serve
  # for both.
  it "is not the balance" do
    collected_job(commission: 50)
    wallet.update!(balance: 2_000)

    get "/admin/courier_wallets/#{wallet.id}"

    expect(page_value("Cash in hand")).to eq("50.00")
    expect(page_value("Balance")).to eq("2000.00")
  end
end
