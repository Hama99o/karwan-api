require "rails_helper"

# ═══ WHAT EACH ENDPOINT ACTUALLY SENDS, ASSERTED AS A WHOLE ════════════════
#
# The sweep's claim is the inverse of the obvious one. Not "does the client get
# the fields it needs" — a missing field is loud, the screen is empty and
# somebody reports it. The dangerous direction is the quiet one: **does the
# response carry a field nobody asked for?** A serializer that starts emitting
# `national_id_number` on a list endpoint is a leak whether or not the owner is
# correct, and every existing spec stays green because they all assert on
# fields they name.
#
# ── WHY THE KEY SET AND NOT A LIST OF FIELDS TO CHECK ────────────────────
#
# A sweep that names the fields it worries about has its domain chosen by
# whoever wrote it — the eighth shape, and the one this repo has now hit three
# times in three instruments. So these assert the WHOLE key set, captured from
# the running endpoint. A field added to any serializer turns its endpoint red
# and somebody has to decide, in that moment, whether a client should see it.
#
# THE SETS BELOW WERE CAPTURED FROM REAL RESPONSES, not typed from the
# serializer source. That matters: a serializer's declared fields and its
# rendered keys differ wherever a `view` is involved, and the rendered keys are
# what reaches a phone.
#
# When one of these goes red, the fix is NOT to paste the new key in. It is to
# ask whether the field belongs on that screen, and only then to paste it in.
#
# ── WHAT THIS ADDS, MEASURED RATHER THAN CLAIMED ─────────────────────────
#
# Two endpoints already had a targeted version of this and they are good:
# `public/merchants_spec.rb:103` ("never exposes the commission rate, the
# owner's identity or the licence") and `merchants/orders_spec.rb:141` ("never
# exposes the customer's delivery address"). Planting
# `owner_national_id_number` on the browse card turns the first of those red as
# well as this one, and that is worth saying plainly — this is not the only
# thing standing between us and that leak.
#
# **The other seven endpoints here had nothing.** And on the two that are
# covered, the existing specs name the fields they worry about, so they catch a
# leak somebody ANTICIPATED. These catch the field nobody thought of, which is
# the only kind that actually ships.
RSpec.describe "payload key sets" do
  def keys_of(node)
    node.is_a?(Array) ? node.first.keys.sort : node.keys.sort
  end

  describe "the customer's screens", type: :request do
    let(:customer) { create(:user, :customer) }
    let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(customer).last}" } }
    let!(:merchant) { create(:merchant, is_open: true) }

    it "the browse card carries exactly these" do
      get "/api/v1/public/merchants"

      expect(keys_of(JSON.parse(response.body)["merchants"])).to eq(%w[
        accepting_orders categories distance_km distance_source eta_minutes
        hours_known id is_open kind kind_name logo_url name next_opens_at
        prep_time_minutes storefront_photo_url
      ])
    end

    # A shop's own phone is public ON PURPOSE — a customer ringing a restaurant
    # is normal and AFGHAN_UX says support is a human. It is listed here so that
    # remains a decision somebody made rather than a field nobody noticed.
    it "the merchant page carries exactly these, including the shop's phone" do
      get "/api/v1/public/merchants/#{merchant.id}"

      expect(keys_of(JSON.parse(response.body)["merchant"])).to eq(%w[
        accepting_orders categories distance_km distance_source eta_minutes
        hours_known id is_open kind kind_name landmark_note location logo_url
        name next_opens_at opening_hours phone prep_time_minutes
        storefront_photo_url
      ])
    end

    it "their own profile carries exactly these" do
      get "/api/v1/me", headers: auth

      expect(keys_of(JSON.parse(response.body)["user"])).to eq(%w[
        active_role avatar_url can_switch_roles id locale name phone
        phone_verified roles
      ])
    end

    it "their own order carries exactly these" do
      order = create(:order, :delivered, customer: customer, merchant: merchant)

      get "/api/v1/customer/orders/#{order.id}", headers: auth

      expect(keys_of(JSON.parse(response.body)["order"])).to eq(%w[
        amount_to_pay_in_cash can_cancel code courier courier_arrived_at currency
        customer_phone customer_total delivery_fee delivery_landmark_note
        delivery_location distance_source id is_live item_count items items_total
        merchant_id merchant_name merchant_phone notes pin_far_from_road
        placed_at status suggested_notes timeline
      ])
    end

    # The list is deliberately thinner than the detail. If these two ever match,
    # the list has started shipping a detail payload 20 times over.
    it "the order list is thinner than the order page" do
      create(:order, :delivered, customer: customer, merchant: merchant)

      get "/api/v1/customer/orders", headers: auth

      summary = keys_of(JSON.parse(response.body)["orders"])
      expect(summary).to eq(%w[
        amount_to_pay_in_cash code courier_arrived_at currency customer_total
        delivery_fee id is_live item_count items_total merchant_id merchant_name
        placed_at status suggested_notes
      ])
      expect(summary).not_to include("items", "timeline", "courier")
    end
  end

  describe "the courier's screens", type: :request do
    let(:courier) { create(:user, :courier) }
    let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(courier).last}" } }

    before { courier.courier_wallet.update!(balance: 800, credit_line: 500) }

    it "the wallet carries exactly these" do
      get "/api/v1/courier/wallet", headers: auth

      expect(keys_of(JSON.parse(response.body)["wallet"])).to eq(%w[
        available_credit balance blocked cash_allowance_remaining cash_in_hand
        credit_line currency floor id low_balance must_settle today top_up_code
        top_up_instructions
      ])
    end

    it "the active job carries exactly these" do
      create(:order, :picked_up, courier: courier)

      get "/api/v1/courier/job", headers: auth

      expect(keys_of(JSON.parse(response.body)["job"])).to eq(%w[
        advance_required arrived_at can_be_combined code currency earnings id
        items kind problem_reasons service_tier status steps total_to_collect
      ])
    end
  end

  describe "the merchant's screens", type: :request do
    let(:owner) { create(:user, :merchant_owner) }
    let!(:merchant) { create(:merchant, owner: owner, is_open: true) }
    let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(owner).last}" } }

    # A merchant's board shows `merchant_payout` — what THEY are paid — and not
    # `commission` or `customer_total`. That is Model A made visible: the shop
    # is paid at pickup and our margin is not their business.
    it "the order board carries exactly these, and not our margin" do
      create(:order, :ready, merchant: merchant)

      get "/api/v1/merchant/orders", headers: auth

      board = keys_of(JSON.parse(response.body)["orders"])
      expect(board).to eq(%w[
        accepted_at code courier currency id is_overdue item_count items
        items_total merchant_payout minutes_in_state notes placed_at ready_at
        status
      ])
      expect(board).not_to include("commission", "courier_fee", "customer_total")
    end

    it "their own profile carries exactly these" do
      get "/api/v1/merchant/profile", headers: auth

      expect(keys_of(JSON.parse(response.body)["profile"])).to eq(%w[
        accepting_orders commission_rate contact_person_name contact_person_phone
        id is_open kind landmark_note location name phone prep_time_minutes
        status today verified
      ])
    end
  end
end
