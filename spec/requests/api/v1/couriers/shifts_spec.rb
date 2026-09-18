require "rails_helper"

# ═══ THE ENDPOINT THE COURIER APP HITS MOST, AND IT HAD NO SPEC ════════════
#
# `ShiftsController`'s own comment: "The availability toggle is the first thing
# on the courier's screen, so this is the endpoint the app hits most often after
# position." It had **no request spec at all** — `bin/gates couriers` listed
# five courier request specs on 2026-09-18 and none of them was this one, and
# `grep -rl "courier/shift" spec/` returned nothing.
#
# CLAUDE.md correction 11 is explicit that this counts as not done: "every
# method, every function, every controller... a controller without a request
# spec covering both the happy path and the forbidden path is not done."
#
# ── What was actually unwatched, and it is money ──────────────────────────
#
# `update` refuses to put a courier ON shift when their wallet is blocked, and
# returns the `top_up_code` with the refusal. That is not a duplicate of
# `Dispatch::Eligibility`'s `:wallet_blocked`, which is tested: eligibility
# decides whether to OFFER a job, and runs when an order appears. This runs when
# the courier presses the toggle, and it is the only path that tells them WHY
# and HOW to fix it. Without it they go online, receive nothing, and conclude
# the app is broken — which is the failure the controller comment describes.
#
# ── Deliberately NOT repeated here ────────────────────────────────────────
#
# The tokenless (401) and wrong-role (403) cases for all three actions are
# derived per-route by `authorization_boundary_spec.rb`. Writing them again is
# the duplicate `bin/gates` exists to prevent, so this file covers what is
# specific to shifts: the approval gate, the wallet gate, and the payload.
RSpec.describe "Api::V1::Couriers::Shifts", type: :request do
  def json
    JSON.parse(response.body)
  end

  let(:courier) { create(:user, :courier) }
  let(:profile) { courier.courier_profile }
  let(:wallet) { courier.courier_wallet }
  let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(courier).last}" } }

  before { wallet.update!(balance: 800, credit_line: 500) }

  describe "GET /api/v1/courier/shift" do
    it "reports availability, the wallet and the cash they are holding" do
      profile.update!(is_available: true)

      get "/api/v1/courier/shift", headers: auth

      expect(response).to have_http_status(:ok)
      expect(json["is_available"]).to be true
      expect(json["accepted_job_kinds"]).to eq(profile.accepted_job_kinds.map(&:to_s))
      expect(json.dig("wallet", "balance").to_f).to eq(800)
      expect(json.dig("wallet", "available_credit").to_f).to eq(1_300)
      expect(json.dig("wallet", "blocked")).to be false
      # The toggle screen shows the same cash figures as the wallet screen, so
      # a courier never sees two different answers to "what am I holding?".
      expect(json).to have_key("cash_in_hand")
      expect(json).to have_key("cash_allowance_remaining")
    end

    # Dispatch will not offer to a courier whose position is stale, so the app
    # has to know before the courier wonders why it has gone quiet.
    it "says the position is stale until one is reported" do
      get "/api/v1/courier/shift", headers: auth
      expect(json["location_fresh"]).to be false

      profile.record_location!(latitude: 34.5553, longitude: 69.2075)

      get "/api/v1/courier/shift", headers: auth
      expect(json["location_fresh"]).to be true
    end

    # The read side of live tracking was capped and the write side was not.
    # Exercised rather than asserted from the config, because a limit that is
    # declared and not wired is the shape of check this project keeps finding.
    it "caps a runaway position loop, which a bad connection makes the normal case" do
      1_201.times do
        post "/api/v1/courier/shift/location",
             params: { latitude: 34.5553, longitude: 69.2075 }, headers: auth
      end

      expect(response).to have_http_status(:too_many_requests)
    end

    it "refuses a courier who is not approved yet" do
      profile.update!(verification_status: :pending)

      get "/api/v1/courier/shift", headers: auth

      expect(response).to have_http_status(:forbidden)
      expect(json["code"]).to eq("not_approved")
    end
  end

  describe "PATCH /api/v1/courier/shift" do
    it "puts them on shift" do
      patch "/api/v1/courier/shift", params: { is_available: true }, headers: auth

      expect(response).to have_http_status(:ok)
      expect(json["is_available"]).to be true
      expect(profile.reload.is_available).to be true
    end

    it "takes them off shift" do
      profile.update!(is_available: true)

      patch "/api/v1/courier/shift", params: { is_available: false }, headers: auth

      expect(json["is_available"]).to be false
      expect(profile.reload.is_available).to be false
    end

    # ── THE MONEY GATE ─────────────────────────────────────────────────────
    it "refuses to put a blocked wallet on shift, and says how to fix it" do
      wallet.update!(balance: -500)
      expect(wallet.reload).to be_blocked, "the wallet is not blocked — the refusal below would prove nothing"

      patch "/api/v1/courier/shift", params: { is_available: true }, headers: auth

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("wallet_blocked")
      # The code, not a sentence: the server cannot explain a bank deposit in
      # Pashto, and a courier who is told "no" without being told "how" is a
      # courier who stops working.
      expect(json["top_up_code"]).to eq(wallet.top_up_code)
      expect(profile.reload.is_available).to be false
    end

    # A courier must ALWAYS be able to stop working. Gating the off switch on
    # the wallet would strand somebody mid-shift with no way to go offline.
    it "still lets a blocked courier go OFF shift" do
      profile.update!(is_available: true)
      wallet.update!(balance: -500)

      patch "/api/v1/courier/shift", params: { is_available: false }, headers: auth

      expect(response).to have_http_status(:ok)
      expect(profile.reload.is_available).to be false
    end
  end

  describe "POST /api/v1/courier/shift/location" do
    it "records the position and reports when it was taken" do
      post "/api/v1/courier/shift/location",
           params: { latitude: 34.5553, longitude: 69.2075 }, headers: auth

      expect(response).to have_http_status(:ok)
      expect(json["recorded_at"]).to be_present
      expect(profile.reload.coordinates.map(&:to_f)).to eq([ 34.5553, 69.2075 ])
      expect(profile).to be_location_fresh
    end

    it "refuses a courier who is not approved yet" do
      profile.update!(verification_status: :pending)

      post "/api/v1/courier/shift/location",
           params: { latitude: 34.5553, longitude: 69.2075 }, headers: auth

      expect(response).to have_http_status(:forbidden)
    end
  end
end
