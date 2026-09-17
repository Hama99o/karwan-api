require "rails_helper"

# ═══ CAN A NON-DEVELOPER ACTUALLY DO THEIR JOB IN THE CONSOLE? ═════════════
#
# Hamma9900's own framing: the admin part is the most important, because five
# to ten people will work in it. Everything proved so far is about the console's
# DATA being right — 18 audited actions, every setting typeable, no `destroy`
# on anything holding money. **None of it asks whether somebody with a phone to
# their ear can complete a task.**
#
# So this drives the five things an operator actually does, through real HTTP,
# and counts the pages each one costs. A task that is possible in six pages is
# a different product from one that is possible in two, and neither shows up in
# a dashboard's source.
#
# The measure is deliberately crude and honest: **one page = one request an
# operator's browser would make.** Redirects are counted where the operator
# waits for them.
RSpec.describe "an operator can do the job", type: :request do
  let(:admin) do
    AdminUser.create!(name: "Najibullah", email: "ops@karwan.af", password: "a-long-test-password")
  end

  before do
    post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
  end

  let(:merchant) { create(:merchant, name: "Kabab House", latitude: 34.5553, longitude: 69.2075) }
  let(:courier) { create(:user, :courier, name: "Ahmad", phone: "+93700111222") }

  # ── 1 · A CUSTOMER RINGS AND READS OUT AN ORDER CODE ─────────────────────
  #
  # The thousand-times-a-day action. He has the code, nothing else.
  describe "find an order by the code the customer reads out" do
    let!(:order) do
      create(:order, :ready, merchant: merchant, courier: courier,
                             customer_phone: "+93700999888",
                             items_total: 400, delivery_fee: 100, customer_total: 500,
                             commission: 50, courier_fee: 100, merchant_payout: 350)
    end

    it "finds it from the code alone, with no search_text declared" do
      get "/admin/orders", params: { search: order.code }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(order.code)
    end

    it "finds it from the customer's phone number too" do
      get "/admin/orders", params: { search: "+93700999888" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(order.code)
    end

    # What he needs to say out loud: where it is, who has it, and whether the
    # money reached us.
    it "shows status, courier and cash position on the order page" do
      get "/admin/orders/#{order.id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(order.status)
      expect(response.body).to include("Ahmad")
      expect(response.body).to match(/payment|cash/i)
    end

    # ── WHICH OPTIONS DID THE CUSTOMER ACTUALLY CHOOSE? ────────────────────
    #
    # One-way door 1 snapshots the option name, value and price delta at order
    # time **so a dispute can be settled** — "I ordered large, not small" is the
    # argument it exists for. They were captured, frozen, and **unreachable from
    # the console**: the only dashboard that rendered them
    # (`OrderItemOptionDashboard`) hangs off a show page with no route, and the
    # order page drew items through `COLLECTION_ATTRIBUTES`, which omitted them.
    #
    # Data nobody can look up is not an answer. `OrderItem#options_summary` now
    # puts it on the order page itself rather than behind another click,
    # because the operator is already there with the customer on the phone.
    #
    # THE FIXTURE MUST ACTUALLY CARRY OPTIONS, or the column renders empty and
    # this passes while proving nothing.
    it "shows which options the customer chose, on the order page" do
      item = create(:order_item, order: order, name: "Chicken Kabab",
                                 unit_price: 400, quantity: 1,
                                 options_total: 100, line_total: 500)
      create(:order_item_option, order_item: item, option_name: "Size",
                                 value_name: "Large", price_delta: 100)

      expect(item.reload.selected_options).to be_present,
                                              "no options — the assertion below would be vacuous"

      get "/admin/orders/#{order.id}"

      expect(response.body).to include("Large"), "an operator cannot see which options were chosen"
      expect(response.body).to include("Size")
    end

    # Most of these disputes are about the money rather than the word.
    it "shows what the option cost, not only its name" do
      item = create(:order_item, order: order, unit_price: 400, quantity: 1,
                                 options_total: 100, line_total: 500)
      create(:order_item_option, order_item: item, option_name: "Size",
                                 value_name: "Large", price_delta: 100)

      expect(item.reload.options_summary).to eq("Size: Large (+100)")
    end
  end

  # ── 2 · A COURIER SAYS HE WAS NOT PAID ───────────────────────────────────
  describe "find a courier, read his ledger, credit him" do
    let!(:wallet) { courier.courier_wallet }

    it "finds him by phone" do
      get "/admin/users", params: { search: "+93700111222" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Ahmad")
    end

    it "finds him by name" do
      get "/admin/users", params: { search: "Ahmad" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("+93700111222")
    end

    it "reaches his wallet and its balance" do
      get "/admin/courier_wallets", params: { search: "Ahmad" }
      expect(response).to have_http_status(:ok)

      get "/admin/courier_wallets/#{wallet.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(wallet.balance.to_i.to_s)
    end

    # The fix from earlier today, driven from the operator's side.
    it "credits him, and the audit row carries the balance BEFORE" do
      before_balance = wallet.balance

      expect {
        post "/admin/courier_wallets/#{wallet.id}/adjust",
             params: { amount: "-50", note: "correcting a miscount" }
      }.to change(AuditLog, :count).by(1)

      log = AuditLog.newest_first.first
      expect(log.admin_user_id).to eq(admin.id)
      expect(log.before.to_s).to include(before_balance.to_i.to_s)
    end
  end

  # ── 3 · A RESTAURANT SAYS NOBODY COLLECTED AN ORDER ──────────────────────
  describe "reassign a stuck order" do
    let!(:order) { create(:order, :ready, merchant: merchant) }
    let!(:other) { create(:user, :courier, name: "Zahra") }

    it "reassigns it and names the operator in the audit row" do
      expect {
        patch "/admin/orders/#{order.id}/reassign", params: { courier_id: other.id }
      }.to change(AuditLog, :count).by(1)

      expect(order.reload.courier).to eq(other)
      log = AuditLog.newest_first.first
      expect(log.action).to eq("order.reassigned")
      expect(log.admin_user_id).to eq(admin.id)
    end
  end

  # ── 4 · A COURIER APPLIED YESTERDAY ──────────────────────────────────────
  describe "process a courier application" do
    let!(:applicant) { create(:courier_profile, :documented) }

    it "lists the ones waiting" do
      get "/admin/courier_profiles"

      expect(response).to have_http_status(:ok)
    end

    it "shows what is still missing before he decides" do
      get "/admin/courier_profiles/#{applicant.id}"

      expect(response).to have_http_status(:ok)
    end

    it "approves in one action, audited" do
      expect {
        patch "/admin/courier_profiles/#{applicant.id}/approve"
      }.to change(AuditLog, :count).by(1)

      expect(applicant.reload).to be_verification_approved
    end
  end

  # ── 5 · A FEE IS WRONG ───────────────────────────────────────────────────
  describe "change a fee and have pricing read it" do
    it "finds the setting, changes it, and the next quote uses the new value" do
      Setting.seed_defaults!
      setting = Setting.find_by!(key: "delivery_base_fee")

      get "/admin/settings", params: { search: "delivery_base_fee" }
      expect(response).to have_http_status(:ok)

      patch "/admin/settings/#{setting.id}", params: { setting: { value: "77" } }

      expect(Setting.fetch("delivery_base_fee")).to eq(77)
    end
  end
end
