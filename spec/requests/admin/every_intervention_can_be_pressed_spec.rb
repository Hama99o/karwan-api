require "rails_helper"

# ═══ EVERY INTERVENTION CAN BE PRESSED BY A PERSON, NOT ONLY REQUESTED BY URL ═
#
# Until 24 Sept 2026 the console's interventions were ROUTES with no form.
# Rendered and counted: the order page, the wallet page, the courier page and
# the user page carried **zero forms**; the only pressable intervention in the
# whole console was the board's Redispatch — the one that offered a carried
# order to another courier. Every existing spec drove the routes by URL, so all
# of it was green while no operator could reassign an order or credit a wallet.
#
# `CLAUDE.md`: *"Build the manual override FIRST — it is what makes the
# business operable."* A route nobody can press is not an override.
#
# ── SO THIS FILE NEVER TYPES A URL ────────────────────────────────────────
#
# `press` opens the record's page, finds the form by the ACTION it posts to,
# fills the fields it names, and submits to the form's own `action` with its
# own method. If the page stops rendering the form, the example fails at
# "no form for …" — the one failure every URL-driven spec was blind to.
RSpec.describe "every intervention can be pressed", type: :request do
  let(:admin) { AdminUser.create!(name: "Najibullah", email: "ops@karwan.af", password: "a-long-test-password") }
  let(:merchant) { create(:merchant, name: "Kabab House") }

  before do
    post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
  end

  # Opens `page`, finds the form posting to an action ending in `action`, and
  # submits it with `fields`. Returns the form's field names so an example can
  # also assert what the operator is asked for.
  def press(page, action, fields = {})
    get page
    expect(response).to have_http_status(:ok)
    form = Nokogiri::HTML(response.body).css("form").detect { |f| f["action"].to_s.end_with?("/#{action}") }
    expect(form).to be_present, "no form for #{action} on #{page} — an operator cannot press it"

    verb = form.at_css("input[name=_method]")&.[]("value") || form["method"]
    names = form.css("input, select").map { |i| i["name"] }.compact - %w[_method authenticity_token]
    unknown = fields.keys.map(&:to_s) - names
    expect(unknown).to be_empty, "the form on #{page} has no field #{unknown.join(', ')} (it has #{names.join(', ')})"

    send(verb.downcase, form["action"], params: fields)
    names
  end

  def pressable?(page, action)
    get page
    Nokogiri::HTML(response.body).css("form").any? { |f| f["action"].to_s.end_with?("/#{action}") }
  end

  describe "an order" do
    let(:courier) { create(:user, :courier, name: "Ahmad") }
    let(:other) { create(:user, :courier, name: "Bilal") }

    it "is reassigned by choosing a courier from the page" do
      order = create(:order, :with_items, :ready, merchant: merchant, courier: courier)
      other

      press("/admin/orders/#{order.id}", "reassign", courier_id: other.id)

      expect(order.reload.courier_id).to eq(other.id)
      expect(AuditLog.where(action: "order.reassigned", target: order, admin_user: admin)).to exist
    end

    it "is cancelled from the page" do
      order = create(:order, :with_items, :accepted, merchant: merchant)

      press("/admin/orders/#{order.id}", "cancel", reason: "shop rang, out of rice")

      expect(order.reload.status).to eq("cancelled")
    end

    it "is marked failed from the page, with a reason from the list" do
      order = create(:order, :with_items, :picked_up, merchant: merchant, courier: courier)

      press("/admin/orders/#{order.id}", "fail", reason: "nobody_home")

      expect(order.reload).to have_attributes(status: "failed", failure_reason: "nobody_home")
    end

    it "offers only what the state allows: no cancel once picked up, no reassign once the shop is paid" do
      order = create(:order, :with_items, :picked_up, merchant: merchant, courier: courier, merchant_paid_at: 1.minute.ago)

      expect([ pressable?("/admin/orders/#{order.id}", "cancel"),
               pressable?("/admin/orders/#{order.id}", "reassign"),
               pressable?("/admin/orders/#{order.id}", "fail") ]).to eq([ false, false, true ])
    end

    it "shows Redispatch on the board only for an order nobody has" do
      taken = create(:order, :with_items, :ready, merchant: merchant, courier: courier)
      free = create(:order, :with_items, :ready, merchant: merchant)

      expect([ pressable?("/admin/orders", "#{taken.id}/redispatch"),
               pressable?("/admin/orders", "#{free.id}/redispatch") ]).to eq([ false, true ])
    end
  end

  describe "a courier's wallet" do
    let(:courier) { create(:user, :courier) }
    let(:wallet) { courier.courier_wallet }
    let(:page) { "/admin/courier_wallets/#{wallet.id}" }

    it "records a bank top-up" do
      expect { press(page, "top_up", amount: "500", note: "HBL 4471") }
        .to change { wallet.reload.balance }.by(500)
    end

    it "reimburses and adjusts, each through the ledger" do
      press(page, "reimburse", amount: "270", note: "K123456 refused at the door")
      press(page, "adjust", amount: "-20", note: "double-counted top-up")

      expect(wallet.wallet_entries.pluck(:kind, :amount).map { |k, a| [ k, a.to_i ] })
        .to include([ "reimbursement", 270 ], [ "adjustment", -20 ])
    end

    it "records a settlement, asking for the deposit's time" do
      create(:order, :with_items, :delivered, merchant: merchant, courier: courier, commission: 50,
                                              payment_status: :collected, delivered_at: 2.hours.ago)

      fields = press(page, "settle", counted_amount: "50", counted_by_name: "Bank statement",
                                     deposited_at: 1.hour.ago.strftime("%Y-%m-%dT%H:%M"))

      expect(fields).to include("deposited_at")
      expect(Settlement.last).to have_attributes(expected_amount: 50, counted_amount: 50)
    end
  end

  describe "a courier's application" do
    # `:documented`: approval is made against the tazkira and the selfie, so an
    # application without them is refused — correctly — with the button there.
    def applicant
      create(:courier_profile, :documented)
    end

    it "is approved from the page" do
      profile = applicant

      press("/admin/courier_profiles/#{profile.id}", "approve")

      expect(profile.reload.verification_status).to eq("approved")
    end

    it "is rejected with a reason, or sent back for more" do
      asked = applicant
      refused = applicant

      press("/admin/courier_profiles/#{asked.id}", "ask_for_more", note: "tazkira photo is blurred")
      press("/admin/courier_profiles/#{refused.id}", "reject", reason: "guarantor did not answer")

      expect([ asked.reload.verification_status, refused.reload.verification_status ])
        .to eq(%w[needs_more rejected])
    end

    it "takes an approved courier off shift" do
      profile = create(:user, :courier).courier_profile
      profile.update!(is_available: true)

      press("/admin/courier_profiles/#{profile.id}", "take_off_shift")

      expect(profile.reload.is_available).to be(false)
    end
  end

  # The launch RUNBOOK tells an operator what to press, in bold. Its words and
  # the page's must be the same words — step 5 is "On the merchant's page,
  # **Open now**", and the button said "Open it".
  it "labels the shop's switch with the words the RUNBOOK tells an operator to press" do
    runbook = Rails.root.join("docs/RUNBOOK.md").read
    closed = create(:merchant, is_open: false)
    open_shop = create(:merchant, is_open: true)

    labels = [ closed, open_shop ].map do |shop|
      get "/admin/merchants/#{shop.id}"
      Nokogiri::HTML(response.body).css("form[action$='_merchant'] [type=submit]").map { |b| b["value"] || b.text.strip }
    end

    expect(labels).to eq([ [ "Open now" ], [ "Close now" ] ])
    expect(runbook).to include("**Open now**").and include("**Close now**")
  end

  describe "a shop" do
    it "is closed on its behalf, and opened again" do
      merchant.update!(is_open: true)

      press("/admin/merchants/#{merchant.id}", "close_merchant")
      closed = merchant.reload.is_open
      press("/admin/merchants/#{merchant.id}", "open_merchant")

      expect([ closed, merchant.reload.is_open ]).to eq([ false, true ])
    end

    it "is suspended with a reason, and approved" do
      pending_shop = create(:merchant, status: :pending)

      press("/admin/merchants/#{merchant.id}", "suspend", reason: "hygiene complaint")
      press("/admin/merchants/#{pending_shop.id}", "approve")

      expect([ merchant.reload.status, pending_shop.reload.status ]).to eq(%w[suspended active])
    end
  end

  describe "an account" do
    let(:user) { create(:user, :customer) }

    it "is signed out of every device — the lost-phone answer" do
      UserSession.issue!(user)

      press("/admin/users/#{user.id}", "revoke_sessions")

      expect(user.reload.live_session_count).to eq(0)
    end

    it "is suspended and reinstated" do
      press("/admin/users/#{user.id}", "suspend", reason: "abusive to couriers")
      suspended = user.reload.status
      press("/admin/users/#{user.id}", "reinstate")

      expect([ suspended, user.reload.status ]).to eq(%w[suspended active])
    end
  end
end
