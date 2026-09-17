require "rails_helper"

# ═══ ONE-WAY DOOR 5, AS A GATE RATHER THAN A HABIT ═════════════════════════
#
# CLAUDE.md: *an audit row for every intervention — who reassigned, who
# cancelled, who credited a wallet, before and after.* And the sentence that
# makes it a one-way door: **unanswerable later if nobody wrote it.** Unlike
# almost anything else, this cannot be fixed retrospectively. A row that was
# never written does not exist, and the question it would have answered — who
# moved this courier's money, and what was the balance before — has no other
# source.
#
# `spec/requests/admin/interventions_spec.rb` asserts what the audit rows
# CONTAIN, action by action, and it is the better spec. This one asserts
# something it cannot: that **no admin action exists without one.**
#
# ── WHY IT ENUMERATES FROM THE ROUTES ────────────────────────────────────
#
# A hand-written list of actions is a denominator that drifts from reality
# silently — the same failure as an orphaned flow, and the same reason a count
# is not a mapping. `ROUTED` is asked of `Rails.application.routes` at load
# time, so **an admin action added tomorrow appears here whether or not anybody
# remembers this file**, and the coverage example turns red until it is driven.
#
# Today has shown four separate times that *written and correct* is a different
# property from *consulted*: `OrderPolicy#track?`, edu-safi's unconsulted
# scope, a preflight check nobody ran, and a linter that could not fail. An
# audit rule living only in a reviewer's memory is the next instance, and it
# would decay from the day it was last checked.
RSpec.describe "every admin intervention is audited", type: :request do
  STANDARD_CRUD = %w[index show new edit create update destroy].freeze

  # Asked of the router, never typed out.
  ROUTED = Rails.application.routes.routes.filter_map { |route|
    controller = route.defaults[:controller]
    action = route.defaults[:action]
    next unless controller&.start_with?("admin/")
    next if STANDARD_CRUD.include?(action)

    "#{controller}##{action}"
  }.uniq.freeze

  let(:admin) do
    AdminUser.create!(name: "Najibullah", email: "ops@karwan.af", password: "a-long-test-password")
  end

  before do
    post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
  end

  let(:merchant) { create(:merchant, latitude: 34.5553, longitude: 69.2075) }
  let(:courier) { create(:user, :courier) }
  let(:order) { create(:order, :ready, merchant: merchant) }

  # Each case drives the action in a state where it actually DOES something —
  # an action that bails out early writes no row, correctly, and would make
  # this gate green for the wrong reason.
  def drive(key)
    case key
    when "admin/orders#reassign"
      patch "/admin/orders/#{order.id}/reassign", params: { courier_id: courier.id }
    when "admin/orders#cancel"
      patch "/admin/orders/#{order.id}/cancel", params: { reason: "customer changed their mind" }
    when "admin/orders#fail"
      # `failed` is reachable only from `picked_up` (Order::TRANSITIONS), and
      # an action that bails out early writes no row — correctly. Driving it
      # from `ready` made this gate red for the wrong reason.
      failable = create(:order, :picked_up, merchant: merchant, courier: courier)
      patch "/admin/orders/#{failable.id}/fail", params: { reason: Order.failure_reasons.keys.first }
    when "admin/orders#redispatch"
      patch "/admin/orders/#{order.id}/redispatch"
    when "admin/merchants#open_merchant"
      patch "/admin/merchants/#{merchant.id}/open_merchant"
    when "admin/merchants#close_merchant"
      patch "/admin/merchants/#{merchant.id}/close_merchant"
    when "admin/merchants#approve"
      patch "/admin/merchants/#{create(:merchant, status: :pending).id}/approve"
    when "admin/merchants#suspend"
      patch "/admin/merchants/#{merchant.id}/suspend", params: { reason: "closed for Ramadan" }
    when "admin/courier_profiles#approve"
      patch "/admin/courier_profiles/#{create(:courier_profile, :documented).id}/approve"
    when "admin/courier_profiles#ask_for_more"
      patch "/admin/courier_profiles/#{create(:courier_profile).id}/ask_for_more",
            params: { note: "the tazkira photo is unreadable" }
    when "admin/courier_profiles#reject"
      patch "/admin/courier_profiles/#{create(:courier_profile).id}/reject",
            params: { reason: "documents do not match" }
    when "admin/courier_profiles#take_off_shift"
      patch "/admin/courier_profiles/#{courier.courier_profile.id}/take_off_shift"
    when "admin/courier_wallets#top_up"
      post "/admin/courier_wallets/#{courier.courier_wallet.id}/top_up",
           params: { amount: "500", note: "bank deposit 4417" }
    when "admin/courier_wallets#adjust"
      post "/admin/courier_wallets/#{courier.courier_wallet.id}/adjust",
           params: { amount: "-50", note: "correcting a miscount" }
    when "admin/courier_wallets#reimburse"
      post "/admin/courier_wallets/#{courier.courier_wallet.id}/reimburse",
           params: { amount: "400", note: "customer refused the food" }
    when "admin/courier_wallets#settle"
      create(:order, :delivered, courier: courier, commission: 50)
      post "/admin/courier_wallets/#{courier.courier_wallet.id}/settle",
           params: { counted_amount: "50", counted_by_name: "Najibullah (Kabul office)" }
    when "admin/users#suspend"
      patch "/admin/users/#{courier.id}/suspend", params: { reason: "cash never settled" }
    when "admin/users#reinstate"
      patch "/admin/users/#{courier.id}/reinstate"
    else
      raise "no case for #{key} — add one, or this gate is lying about it"
    end
  end

  # ── THE ANTI-DRIFT PAIR ──────────────────────────────────────────────────
  #
  # `COVERED` is the numerator and `ROUTED` — asked of the router — is the
  # denominator, compared in BOTH directions. An admin action added tomorrow
  # turns the first red; one deleted turns the second red. That is the whole
  # reason the denominator is not a hand-written list.
  COVERED = %w[
    admin/orders#reassign admin/orders#cancel admin/orders#fail admin/orders#redispatch
    admin/merchants#open_merchant admin/merchants#close_merchant
    admin/merchants#approve admin/merchants#suspend
    admin/courier_profiles#approve admin/courier_profiles#ask_for_more
    admin/courier_profiles#reject admin/courier_profiles#take_off_shift
    admin/courier_wallets#top_up admin/courier_wallets#adjust
    admin/courier_wallets#reimburse admin/courier_wallets#settle
    admin/users#suspend admin/users#reinstate
  ].freeze

  it "drives every custom admin action the routes define" do
    expect(ROUTED - COVERED).to be_empty,
                                "not covered by the audit gate: #{(ROUTED - COVERED).join(', ')}"
  end

  it "does not claim to cover an action the routes no longer have" do
    expect(COVERED - ROUTED).to be_empty,
                                "covered but no longer routed: #{(COVERED - ROUTED).join(', ')}"
  end

  ROUTED.each do |key|
    it "#{key} writes an audit row naming the admin who did it" do
      expect { drive(key) }.to change(AuditLog, :count).by(1)

      log = AuditLog.newest_first.first
      expect(log.admin_user_id).to eq(admin.id), "#{key} recorded no actor"
      expect(log.action).to be_present
    end
  end

  # A money movement's audit row must carry the balance on BOTH sides:
  # "what was his balance before somebody adjusted it" is the question the row
  # exists to answer, and an `after` alone cannot answer it.
  it "records both sides of a wallet movement, not just the new balance" do
    wallet = courier.courier_wallet
    before_balance = wallet.balance

    post "/admin/courier_wallets/#{wallet.id}/adjust",
         params: { amount: "-50", note: "correcting a miscount" }

    log = AuditLog.newest_first.first
    expect(log.before).to be_present, "a wallet adjustment recorded no BEFORE"
    expect(log.before.to_s).to include(before_balance.to_i.to_s)
  end
end
