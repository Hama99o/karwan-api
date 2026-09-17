require "rails_helper"

# THE INTERVENTIONS ARE THE POINT of the console. A default Administrate
# install gives a CRUD form; what makes a delivery business operable is being
# able to reassign a courier, cancel an order, credit a wallet or count the cash
# — each one logged with who did it, which a generic form edit could never
# record.
RSpec.describe "Admin interventions", type: :request do
  let(:admin) { AdminUser.create!(name: "Najibullah", email: "ops@karwan.af", password: "a-long-test-password") }

  before do
    post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
  end

  def last_log(action)
    AuditLog.where(action: action).newest_first.first
  end

  describe "orders" do
    let(:merchant) { create(:merchant, latitude: 34.5553, longitude: 69.2075) }
    let(:order) { create(:order, :ready, merchant: merchant) }

    # The manual override CLAUDE.md says to build FIRST — it is what keeps the
    # business operable while the automation is wrong.
    describe "reassign" do
      it "hands the order to a named courier, skipping dispatch" do
        courier = create(:user, :courier)

        patch "/admin/orders/#{order.id}/reassign", params: { courier_id: courier.id }

        expect(order.reload.courier_id).to eq(courier.id)
      end

      # ── A HAND-ASSIGNED COURIER IS PAID THE SAME AS AN ALGORITHM-ASSIGNED ONE
      #
      # The distance top-up used to be computed in `offers#accept`, which is
      # NOT the only way a courier is assigned — this path sets `courier`
      # directly. So a courier moved onto a thin far order by hand rode exactly
      # the same dead leg and was silently paid less, and neither order looked
      # wrong on its own.
      #
      # How the courier came to hold the job is not a dimension of the policy.
      # The rule now lives on the assignment itself (`Order#freeze_courier_pay`),
      # so every path gets it, including the ones that do not exist yet.
      it "tops up a thin far order the same as dispatch would have" do
        Setting.find_or_initialize_by(key: "courier_topup_enabled")
               .update!(value: "true", value_type: :boolean)
        Setting.find_or_initialize_by(key: "courier_min_earnings_per_km")
               .update!(value: "20", value_type: :decimal)
        order.update!(distance_km: 6)
        courier = create(:user, :courier)
        courier.courier_profile.update!(last_latitude: merchant.latitude + 0.036,
                                        last_longitude: merchant.longitude,
                                        location_updated_at: Time.current)

        patch "/admin/orders/#{order.id}/reassign", params: { courier_id: courier.id }

        expect(order.reload.commission_topup).to be > 0
      end

      # A reassignment must not leave the PREVIOUS courier's figure on the row:
      # the new courier may be standing at the merchant's door.
      it "clears a top-up the new courier does not qualify for" do
        order.update!(distance_km: 6, commission_topup: 25)
        courier = create(:user, :courier)
        courier.courier_profile.update!(last_latitude: merchant.latitude,
                                        last_longitude: merchant.longitude,
                                        location_updated_at: Time.current)

        patch "/admin/orders/#{order.id}/reassign", params: { courier_id: courier.id }

        expect(order.reload.commission_topup).to eq(0)
      end

      it "names the admin who did it, with the before and after" do
        courier = create(:user, :courier)

        patch "/admin/orders/#{order.id}/reassign", params: { courier_id: courier.id }

        log = last_log("order.reassigned")
        expect(log.admin_user_id).to eq(admin.id)
        expect(log.after["courier_id"]).to eq(courier.id)
        expect(log.ip).to be_present
      end

      # Left alone, the expiry sweep would re-offer work an operator has just
      # assigned by hand.
      it "supersedes any live offer" do
        courier = create(:user, :courier)
        other = create(:user, :courier)
        offer = order.offers.create!(courier: other, sequence: 1, status: :offered,
                                     offered_at: Time.current, expires_at: 1.minute.from_now)

        patch "/admin/orders/#{order.id}/reassign", params: { courier_id: courier.id }

        expect(offer.reload.status).to eq("superseded")
      end
    end

    describe "cancel" do
      it "cancels a live order and records the reason" do
        patch "/admin/orders/#{order.id}/cancel", params: { reason: "merchant phoned, closing early" }

        expect(order.reload.status).to eq("cancelled")
        expect(order.cancelled_by_role).to eq("admin")
        expect(last_log("order.cancelled").details["reason"]).to eq("merchant phoned, closing early")
      end

      it "refuses to cancel an order that is already delivered" do
        delivered = create(:order, :delivered, merchant: merchant)

        patch "/admin/orders/#{delivered.id}/cancel"

        expect(delivered.reload.status).to eq("delivered")
      end
    end

    describe "fail" do
      # Failing an order is a money decision — the platform absorbs the food
      # cost — so the reason is mandatory and from the fixed list, keeping
      # "failure reasons ranked" countable.
      it "marks it failed with a reason from the list" do
        picked_up = create(:order, :picked_up, merchant: merchant)

        patch "/admin/orders/#{picked_up.id}/fail", params: { reason: "customer_refused" }

        expect(picked_up.reload.status).to eq("failed")
        expect(picked_up.failure_reason).to eq("customer_refused")
      end

      it "refuses an invented reason" do
        picked_up = create(:order, :picked_up, merchant: merchant)

        patch "/admin/orders/#{picked_up.id}/fail", params: { reason: "no idea" }

        expect(picked_up.reload.status).to eq("picked_up")
      end
    end

    describe "redispatch" do
      it "offers an unassigned order to an eligible courier" do
        courier = create(:user, :courier)
        courier.courier_profile.update!(is_available: true, last_latitude: 34.5553,
                                        last_longitude: 69.2075, location_updated_at: Time.current)
        courier.courier_wallet.update!(balance: 5_000, credit_line: 500)
        accepted = create(:order, :accepted, merchant: merchant)

        patch "/admin/orders/#{accepted.id}/redispatch"

        expect(accepted.reload.offers.pending.count).to eq(1)
      end

      # "No eligible courier" is a useful answer, not a failure — it tells the
      # operator to phone somebody.
      it "says so when nobody is eligible, and still logs the attempt" do
        accepted = create(:order, :accepted, merchant: merchant)

        patch "/admin/orders/#{accepted.id}/redispatch"

        expect(accepted.reload.offers).to be_empty
        expect(last_log("order.redispatched").details["blocked"]).to eq("no_eligible_courier")
      end
    end
  end

  describe "couriers" do
    # `:documented` — approval is made AGAINST the tazkira and the selfie, so a
    # profile without them is correctly refused now. See the example below.
    let(:profile) { create(:courier_profile, :documented) }

    it "approves a courier and gives them a wallet with the configured credit line" do
      patch "/admin/courier_profiles/#{profile.id}/approve"

      expect(profile.reload.verification_status).to eq("approved")
      wallet = profile.user.reload.courier_wallet
      expect(wallet).to be_present
      expect(wallet.credit_line).to eq(Setting.fetch("default_credit_line"))
    end

    # The three things approval means. The ROLE was never granted at all, which
    # left couriers "approved" and unable to see a single job — every
    # courier-scoped query resolves to `none` without it.
    it "grants the courier ROLE, without which they can see no jobs at all" do
      patch "/admin/courier_profiles/#{profile.id}/approve"

      expect(profile.user.reload.role?(:courier)).to be true
    end

    it "records WHICH admin approved, on the row" do
      patch "/admin/courier_profiles/#{profile.id}/approve"

      # The existing `verified_by` points at `users` and the console operator is
      # an `AdminUser`, so it could only ever be nil — and CLAUDE.md says a nil
      # approver is not a valid state.
      expect(profile.reload.verified_by_admin_user).to eq(admin)
    end

    # An approval made without seeing the documents is a rubber stamp, and the
    # documents are the entire reason they are collected.
    it "refuses to approve an application with no documents attached" do
      undocumented = create(:courier_profile)

      patch "/admin/courier_profiles/#{undocumented.id}/approve"

      expect(undocumented.reload.verification_status).to eq("pending")
      expect(flash[:alert]).to match(/id_document|selfie/)
    end

    # An incomplete application must not be waved through — the tazkira and
    # guarantor are collected precisely so "who let this person in?" has an
    # answer.
    it "refuses to approve without identity and a guarantor" do
      incomplete = create(:courier_profile, full_name: nil, guarantor_phone: nil)

      patch "/admin/courier_profiles/#{incomplete.id}/approve"

      expect(incomplete.reload.verification_status).to eq("pending")
    end

    it "rejects with a mandatory reason" do
      patch "/admin/courier_profiles/#{profile.id}/reject", params: { reason: "documents unreadable" }

      expect(profile.reload.verification_status).to eq("rejected")
      expect(profile.rejection_reason).to eq("documents unreadable")
    end

    it "refuses a rejection with no reason" do
      patch "/admin/courier_profiles/#{profile.id}/reject"

      expect(profile.reload.verification_status).to eq("pending")
    end

    it "takes a courier off shift on their behalf" do
      approved = create(:courier_profile, :dispatchable)

      patch "/admin/courier_profiles/#{approved.id}/take_off_shift"

      expect(approved.reload.is_available).to be false
    end
  end

  describe "wallets" do
    let(:courier) { create(:user, :courier) }
    let(:wallet) { courier.courier_wallet }

    before { wallet.update!(balance: 0, credit_line: 500) }

    # A bank deposit, reconciled from the statement by the courier's 4-digit
    # code rather than by name.
    it "records a top-up as a ledger entry, not a balance edit" do
      expect { post "/admin/courier_wallets/#{wallet.id}/top_up", params: { amount: "1000", note: "bank deposit" } }
        .to change { wallet.reload.balance }.from(0).to(1_000)

      entry = wallet.wallet_entries.last
      expect(entry.kind).to eq("top_up")
      expect(entry.balance_after).to eq(1_000)
      expect(last_log("wallet.topped_up").details["top_up_code"]).to eq(wallet.top_up_code)
    end

    it "refuses a zero or negative top-up" do
      post "/admin/courier_wallets/#{wallet.id}/top_up", params: { amount: "0" }

      expect(wallet.reload.balance).to eq(0)
      expect(wallet.wallet_entries).to be_empty
    end

    it "reimburses a courier the platform's own loss" do
      post "/admin/courier_wallets/#{wallet.id}/reimburse",
           params: { amount: "350", note: "customer refused order K123" }

      expect(wallet.reload.balance).to eq(350)
      expect(wallet.wallet_entries.last.kind).to eq("reimbursement")
    end

    # An adjustment with no explanation is indistinguishable from a mistake six
    # months later.
    it "requires a reason for an adjustment, in either direction" do
      post "/admin/courier_wallets/#{wallet.id}/adjust", params: { amount: "-100" }
      expect(wallet.reload.balance).to eq(0)

      post "/admin/courier_wallets/#{wallet.id}/adjust", params: { amount: "-100", note: "double charge" }
      expect(wallet.reload.balance).to eq(-100)
    end

    describe "settle" do
      # `expected` is COMPUTED from the unsettled jobs, never typed. The whole
      # value of this table is that the two numbers came from different places;
      # a typed expected figure could agree with the counted one by accident.
      it "computes expected from the unsettled jobs and stores both numbers" do
        create(:order, :delivered, courier: courier, commission: 50)
        create(:trip, :completed, courier: courier, fare: 160, commission: 20, courier_earnings: 140)

        post "/admin/courier_wallets/#{wallet.id}/settle",
             params: { counted_amount: "65", counted_by_name: "Najibullah (Kabul office)" }

        settlement = Settlement.last
        expect(settlement.expected_amount).to eq(70)
        expect(settlement.counted_amount).to eq(65)
        expect(settlement.variance).to eq(-5)
        expect(settlement.counted_by_name).to eq("Najibullah (Kabul office)")
      end

      # Marking the jobs settled is what clears the cash-in-hand gate and lets
      # dispatch offer them work again.
      it "clears the courier's cash position" do
        create(:order, :delivered, courier: courier, commission: 50)
        expect(Couriers::CashPosition.new(courier).held).to eq(50)

        post "/admin/courier_wallets/#{wallet.id}/settle",
             params: { counted_amount: "50", counted_by_name: "Najibullah" }

        expect(Couriers::CashPosition.new(courier).held).to eq(0)
      end

      it "refuses without the name of whoever counted it" do
        post "/admin/courier_wallets/#{wallet.id}/settle", params: { counted_amount: "50" }

        expect(Settlement.count).to eq(0)
      end
    end
  end

  describe "merchants" do
    let(:merchant) { create(:merchant, is_open: false) }

    # The single most important control in the system — a merchant marked open
    # that isn't is the most damaging state there is — so it is one click with
    # an audit row rather than a form save.
    it "opens and closes a merchant on its behalf" do
      patch "/admin/merchants/#{merchant.id}/open_merchant"
      expect(merchant.reload.is_open).to be true
      expect(last_log("merchant.opened").details["on_their_behalf"]).to be true

      patch "/admin/merchants/#{merchant.id}/close_merchant"
      expect(merchant.reload.is_open).to be false
    end

    it "approves a pending merchant" do
      pending_merchant = create(:merchant, :pending)

      patch "/admin/merchants/#{pending_merchant.id}/approve"

      expect(pending_merchant.reload.status).to eq("active")
      expect(pending_merchant.verified_at).to be_present
    end

    # A suspended merchant left `is_open` would still look orderable to
    # anything reading that flag alone.
    it "closes a merchant when suspending it" do
      open_merchant = create(:merchant, is_open: true)

      patch "/admin/merchants/#{open_merchant.id}/suspend", params: { reason: "food safety complaint" }

      expect(open_merchant.reload.status).to eq("suspended")
      expect(open_merchant.is_open).to be false
    end

    it "refuses a suspension with no reason" do
      patch "/admin/merchants/#{merchant.id}/suspend"

      expect(merchant.reload.status).to eq("active")
    end
  end

  describe "config" do
    # Editable with no deploy is the whole point — he tunes prices by typing,
    # and the pricing services read these rows on every quote.
    it "changes a price and logs the before and after" do
      Setting.seed_defaults!
      setting = Setting.find_by!(key: "delivery_base_fee")

      patch "/admin/settings/#{setting.id}", params: { setting: { value: "75.0" } }

      expect(Setting.fetch("delivery_base_fee")).to eq(75)
      log = last_log("setting.changed")
      expect(log.before["value"]).to eq("50.0")
      expect(log.after["value"]).to eq("75.0")
      expect(log.admin_user_id).to eq(admin.id)
    end

    it "takes effect on the next quote with no deploy" do
      Setting.seed_defaults!
      merchant = create(:merchant, latitude: 34.5553, longitude: 69.2075)
      before = Pricing::DeliveryQuote.new(merchant: merchant, items_total: 400,
                                          delivery_latitude: 34.5400,
                                          delivery_longitude: 69.1750).call

      setting = Setting.find_by!(key: "delivery_fee_per_km")
      patch "/admin/settings/#{setting.id}", params: { setting: { value: "60.0" } }

      after = Pricing::DeliveryQuote.new(merchant: merchant, items_total: 400,
                                         delivery_latitude: 34.5400,
                                         delivery_longitude: 69.1750).call
      expect(after.amounts[:delivery_fee]).to be > before.amounts[:delivery_fee]
    end
  end

  describe "the audit log screen" do
    it "is readable and shows who did what" do
      order = create(:order)
      patch "/admin/orders/#{order.id}/cancel", params: { reason: "test" }

      get "/admin/audit_logs"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("order.cancelled")
    end

    # An editable audit log is not an audit log, and neither is a deletable
    # one. Asserted against the ROUTE TABLE rather than by making a request:
    # with `show_exceptions = :rescuable` an unroutable request comes back as a
    # 404 rather than raising, so an HTTP expectation here would pass for a
    # route that merely errored.
    it "has no update or destroy route at all" do
      routes = Rails.application.routes.routes.filter_map do |route|
        next unless route.defaults[:controller] == "admin/audit_logs"

        route.defaults[:action]
      end

      expect(routes.uniq.sort).to eq(%w[index show])
    end

    it "has no update or destroy route for the ledger either" do
      routes = Rails.application.routes.routes.filter_map do |route|
        next unless route.defaults[:controller] == "admin/wallet_entries"

        route.defaults[:action]
      end

      expect(routes.uniq.sort).to eq(%w[index show])
    end
  end
end
