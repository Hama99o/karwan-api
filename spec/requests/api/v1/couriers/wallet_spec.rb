require "rails_helper"

RSpec.describe "Api::V1::Couriers::Wallet", type: :request do
  def json
    JSON.parse(response.body)
  end

  let(:courier) { create(:user, :courier) }
  let(:wallet) { courier.courier_wallet }
  let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(courier).last}" } }

  before { wallet.update!(balance: 800, credit_line: 500) }

  describe "GET /api/v1/courier/wallet" do
    it "shows what they have and how far they may go" do
      get "/api/v1/courier/wallet", headers: auth

      expect(response).to have_http_status(:ok)
      w = json["wallet"]
      expect(w["balance"].to_f).to eq(800)
      expect(w["credit_line"].to_f).to eq(500)
      # Stored positive, applied negative — the app should never work that out.
      expect(w["floor"].to_f).to eq(-500)
      expect(w["available_credit"].to_f).to eq(1_300)
      expect(w["blocked"]).to be false
    end

    # PRODUCT.md: top-up instructions showing their OWN 4-digit reference code.
    # Reconciled by code, not by name — names repeat and transliterate badly.
    it "shows their own 4-digit reference code and the instructions" do
      get "/api/v1/courier/wallet", headers: auth

      expect(json.dig("wallet", "top_up_code")).to match(/\A\d{4}\z/)
      instructions = json.dig("wallet", "top_up_instructions")
      expect(instructions["reference_code"]).to eq(wallet.top_up_code)
      # A KEY, not an English sentence: the server cannot explain a bank
      # deposit in Pashto.
      expect(instructions["message_key"]).to eq("courier.wallet.top_up_instructions")
    end

    # At zero they stop earning, so the warning is computed by the server
    # rather than guessed by the app — a client threshold would drift from the
    # one dispatch enforces.
    it "warns when the available credit runs low" do
      get "/api/v1/courier/wallet", headers: auth
      expect(json.dig("wallet", "low_balance")).to be false

      wallet.update!(balance: -400)
      get "/api/v1/courier/wallet", headers: auth

      expect(json.dig("wallet", "low_balance")).to be true
    end

    it "says plainly when the wallet is blocked" do
      wallet.update!(balance: -500)

      get "/api/v1/courier/wallet", headers: auth

      expect(json.dig("wallet", "blocked")).to be true
    end

    # Shown rather than discovered when dispatch goes quiet.
    it "shows our cash they are holding and what is left before settling" do
      create(:order, :delivered, courier: courier, commission: 50)

      get "/api/v1/courier/wallet", headers: auth

      expect(json.dig("wallet", "cash_in_hand").to_f).to eq(50)
      expect(json.dig("wallet", "cash_allowance_remaining").to_f)
        .to eq(Setting.fetch("cash_in_hand_limit") - 50)
      expect(json.dig("wallet", "must_settle")).to be false
    end

    it "tells them when they must settle before taking more work" do
      Setting.seed_defaults!
      Setting.find_by!(key: "cash_in_hand_limit").update!(value: "40")
      create(:order, :delivered, courier: courier, commission: 50)

      get "/api/v1/courier/wallet", headers: auth

      expect(json.dig("wallet", "must_settle")).to be true
    end

    # Today, per PRODUCT.md: deliveries, earnings, cash in hand. Both demand
    # types on one pool, so both count.
    it "shows today's work across deliveries and rides" do
      create(:order, :delivered, courier: courier, courier_fee: 100, commission: 50)
      create(:trip, :completed, courier: courier, fare: 160, commission: 20, courier_earnings: 140)

      get "/api/v1/courier/wallet", headers: auth

      today = json.dig("wallet", "today")
      expect(today["deliveries"]).to eq(1)
      expect(today["rides"]).to eq(1)
      # Grouped by currency, never summed across it.
      expect(today["earnings"]).to eq({ "AFN" => "240.0" })
      expect(today["commission_charged"]).to eq({ "AFN" => "70.0" })
    end

    describe "the refused paths" do
      it "refuses without a token" do
        get "/api/v1/courier/wallet"

        expect(response).to have_http_status(:unauthorized)
      end

      it "refuses a customer" do
        customer = create(:user, :customer)

        get "/api/v1/courier/wallet",
            headers: { "Authorization" => "Bearer #{UserSession.issue!(customer).last}" }

        expect(response).to have_http_status(:forbidden)
        expect(json["code"]).to eq("no_courier_profile")
      end

      it "refuses a courier who is not approved yet" do
        courier.courier_profile.update!(verification_status: :pending)

        get "/api/v1/courier/wallet", headers: auth

        expect(response).to have_http_status(:forbidden)
        expect(json["code"]).to eq("not_approved")
      end

      # Holding the courier role grants nothing — only owning this wallet does.
      it "never shows another courier's wallet" do
        other = create(:user, :courier)
        other.courier_wallet.update!(balance: 99_999)

        get "/api/v1/courier/wallet", headers: auth

        expect(json.dig("wallet", "balance").to_f).to eq(800)
      end
    end
  end

  describe "GET /api/v1/courier/wallet/entries" do
    it "returns the statement, newest first, with a running balance" do
      wallet.record_entry!(kind: :top_up, amount: 1_000, note: "deposit")
      wallet.record_entry!(kind: :commission, amount: -50, source: create(:order))

      get "/api/v1/courier/wallet/entries", headers: auth

      entries = json["wallet_entries"]
      expect(entries.first["kind"]).to eq("commission")
      # Followable line by line — what stops an argument about the balance.
      expect(entries.first["balance_after"].to_f).to eq(1_750)
      expect(entries.last["kind"]).to eq("top_up")
    end

    it "names the job a commission was charged against" do
      order = create(:order)
      wallet.record_entry!(kind: :commission, amount: -50, source: order)

      get "/api/v1/courier/wallet/entries", headers: auth

      job = json["wallet_entries"].first["job"]
      expect(job["kind"]).to eq("delivery")
      expect(job["code"]).to eq(order.code)
    end

    it "leaves the job nil for a top-up, which belongs to no job" do
      wallet.record_entry!(kind: :top_up, amount: 500)

      get "/api/v1/courier/wallet/entries", headers: auth

      expect(json["wallet_entries"].first["job"]).to be_nil
    end

    # A working courier generates entries every day; the screen must not fetch
    # a year of them over a metered connection.
    it "paginates" do
      30.times { wallet.record_entry!(kind: :top_up, amount: 1) }

      get "/api/v1/courier/wallet/entries", params: { page: { number: 1, size: 10 } }, headers: auth

      expect(json["wallet_entries"].size).to eq(10)
      expect(json.dig("meta", "pagination", "total_count")).to eq(30)
    end

    # ── THIS ASSERTED NOTHING UNTIL 2026-09-17 ─────────────────────────────
    #
    # It created another courier's entry and checked this courier's statement
    # did not contain it — but **this courier had no entries at all**, so the
    # exclusion was true of an empty list and would have stayed true if the
    # scope had leaked every entry in the database and then broken for an
    # unrelated reason.
    #
    # A tenancy check that passes on nothing is the worst kind to hold: it is
    # edu-safi's "tenancy is not permission" lesson with no teeth. He now has
    # an entry of his own, so the exclusion is observable.
    # ── AND THEN IT MATCHED ON AMOUNTS, WHICH IS NOT AN IDENTITY ───────────
    #
    # The hardened version above asserted `include(500.0)` and
    # `not_to include(777.0)`. **An amount is not a name.** Any row written by
    # anything else — a seed, a factory default, another session filling the
    # same fixture from the other end — can carry 500 or 777 and either satisfy
    # the positive without the courier's own entry being present, or contradict
    # the exclusion without anything having leaked.
    #
    # It failed once under `config.order = :random` on the evening of
    # 2026-09-17, hours after five new wallet entries were added to the shared
    # seed by another session, and passed on every rerun. The seed was not
    # captured, so the permutation is gone and the mechanism was never proven —
    # **that is recorded as unproven rather than guessed at.** What needs no
    # permutation to see is the shape: a ledger assertion keyed on a VALUE that
    # other writers also produce.
    #
    # Keyed on the row's own id, no row written anywhere else can satisfy it or
    # break it. Note also what made this findable at all: **a vacuous assertion
    # cannot have an order dependency** — it passes regardless. Hardening it is
    # what gave it the capacity to fail.
    it "never shows another courier's entries" do
      mine = courier.courier_wallet.record_entry!(kind: :top_up, amount: 500)
      other = create(:user, :courier)
      theirs = other.courier_wallet.record_entry!(kind: :top_up, amount: 777)

      get "/api/v1/courier/wallet/entries", headers: auth

      ids = json["wallet_entries"].map { |e| e["id"] }
      expect(ids).to include(mine.id),
                     "his own statement is empty — the exclusion below would be vacuous"
      expect(ids).not_to include(theirs.id)
    end
  end

  describe "GET /api/v1/courier/wallet/settlements" do
    # BOTH numbers, plus who counted. A courier told only the variance cannot
    # check it, and "unexplained mismatches are theft" only works if both sides
    # see the same two figures.
    it "shows expected and counted and the name of whoever counted" do
      create(:settlement, :short, courier: courier, expected_amount: 500,
                                  counted_amount: 450, counted_by_name: "Najibullah (Kabul office)")

      get "/api/v1/courier/wallet/settlements", headers: auth

      settlement = json["settlements"].first
      expect(settlement["expected_amount"].to_f).to eq(500)
      expect(settlement["counted_amount"].to_f).to eq(450)
      expect(settlement["variance"].to_f).to eq(-50)
      expect(settlement["short"]).to be true
      expect(settlement["counted_by_name"]).to eq("Najibullah (Kabul office)")
    end

    it "marks a balanced count as balanced" do
      create(:settlement, courier: courier)

      get "/api/v1/courier/wallet/settlements", headers: auth

      expect(json["settlements"].first["balanced"]).to be true
    end

    it "never shows another courier's settlements" do
      create(:settlement, courier: create(:user, :courier), counted_amount: 12_345)

      get "/api/v1/courier/wallet/settlements", headers: auth

      expect(json["settlements"]).to be_empty
    end

    # A courier cannot record their own settlement: the whole point is that the
    # counted figure comes from somebody else.
    it "offers no route for a courier to record one" do
      routes = Rails.application.routes.routes.filter_map do |route|
        next unless route.defaults[:controller] == "api/v1/couriers/wallet"

        route.defaults[:action]
      end

      expect(routes.uniq.sort).to eq(%w[entries settlements show])
    end
  end
end
