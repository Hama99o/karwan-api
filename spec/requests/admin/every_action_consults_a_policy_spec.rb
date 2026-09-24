require "rails_helper"

# ═══ EVERY CONSOLE ACTION, FROM THE ROUTE TABLE — DOES IT ASK A POLICY? ═════
#
# `policies_are_consulted_spec.rb` proves the policies that exist are called.
# It started from the POLICIES, so it could only ever see actions that already
# had one: `reimburse` credited a courier's wallet with no policy method at
# all, and the 18 Sept sweep had nothing to find. A sweep that enumerates what
# is declared is blind to exactly the actions most likely to be unprotected.
#
# So this starts from what is REACHABLE. Every admin route is driven as a
# signed-in admin, and Pundit is asked afterwards whether the action consulted
# a policy (`pundit_policy_authorized?`).
#
# ── THE ANSWER ON 2026-09-24: 6 OF 108, then 6 OF 110, then 10 OF 114 ──────
#
# (The last four are the rides override — reassign, cancel, fail and
# redispatch on admin/trips — which consult TripPolicy, so they joined the
# protected side, not the list below.)
#
# (The two added are catalog restore, the undo for a Delete that now
# discards. They joined the list below in the same commit, which is the
# list working as intended: nothing joins it silently.)
#
# Every other action is gated by `authenticate_admin_user!` and nothing else.
# Administrate's CRUD calls `authorize_resource`, which is a no-op returning
# true unless `Administrate::Punditize` is included — and it is not.
#
# NOTHING IS EXPLOITABLE TODAY, AND THAT IS A COINCIDENCE, NOT A PROPERTY.
# Every console account is an admin with every power, so a missing policy and
# a policy that says `admin?` behave identically. That stops being true the
# first time somebody is given limited access — a cashier who records
# deposits, a support agent who reads orders — and on that day these 104
# actions all say yes to them.
#
# ── WHAT THE LIST BELOW IS ──────────────────────────────────────────────────
#
# Not a set of exemptions. It is the recorded state, so that the suite stays
# green while it is true and goes red the moment it changes in either
# direction:
#   * a NEW action that consults no policy fails until it does, or until it is
#     listed here with a reason — nothing joins this list silently;
#   * a LISTED action that starts consulting a policy fails until it is taken
#     off, so the list cannot keep claiming a gap that was closed.
RSpec.describe "every console action consults a policy", type: :request do
  let(:admin) do
    AdminUser.create!(name: "Najibullah", email: "ops@karwan.af", password: "a-long-test-password")
  end

  # Not in the table. Login and logout run before an identity exists or to end
  # one's own; there is nothing for a policy to be asked about.
  PRE_AUTHENTICATION = "admin/sessions".freeze

  CONSOLE_ACTIONS = Rails.application.routes.routes.filter_map do |route|
    controller = route.defaults[:controller]
    next unless controller&.start_with?("admin/")
    next if controller == PRE_AUTHENTICATION

    verb = route.verb.is_a?(String) ? route.verb : route.verb.source.gsub(/[$^]/, "")
    { controller: controller, action: route.defaults[:action], verb: verb.split("|").first.downcase.to_sym,
      spec: route.path.spec.to_s.sub("(.:format)", "") }
  end.uniq { |r| [ r[:controller], r[:action] ] }

  # Administrate's generated actions. `authorize_resource` is a no-op here
  # because `Administrate::Punditize` is not included, and most of these models
  # have no policy class to include it against.
  CRUD_WITHOUT_POLICY = {
    "admin/orders" => %w[index show],
    "admin/trips" => %w[index show],
    "admin/merchants" => %w[index show new create edit update destroy],
    "admin/courier_profiles" => %w[index show edit update],
    "admin/courier_wallets" => %w[index show edit update],
    "admin/merchant_opening_hours" => %w[index show new create edit update destroy],
    "admin/merchant_categories" => %w[index show new create edit update destroy],
    "admin/catalog_categories" => %w[index show new create edit update destroy],
    "admin/catalog_items" => %w[index show new create edit update destroy],
    "admin/catalog_item_options" => %w[index show new create edit update destroy],
    "admin/catalog_item_option_values" => %w[index show new create edit update destroy],
    "admin/users" => %w[index show edit update],
    "admin/settings" => %w[index show edit update],
    "admin/pricing_rates" => %w[index show new create edit update],
    "admin/audit_logs" => %w[index show],
    "admin/wallet_entries" => %w[index show],
    "admin/courier_shifts" => %w[index show],
    "admin/merchant_statements" => %w[index show],
    "admin/settlements" => %w[index show],
    "admin/reports" => %w[index],
    "admin/dashboard" => %w[index]
  }.freeze

  # Hand-written interventions with no `authorize` line. These change state or
  # access — cancel an order, suspend a shop, end a person's sessions — and
  # they are the first a limited role would have to be refused.
  INTERVENTIONS_WITHOUT_POLICY = {
    "admin/orders" => %w[reassign cancel fail redispatch],
    "admin/merchants" => %w[open_merchant close_merchant approve suspend restore],
    "admin/courier_profiles" => %w[ask_for_more take_off_shift],
    "admin/users" => %w[suspend reinstate restore revoke_sessions],
    # The undo for Delete (which discards), added 24 Sept 2026 in the same
    # shape as merchants#restore — and, like it, gated by the session alone.
    "admin/catalog_items" => %w[restore],
    "admin/catalog_categories" => %w[restore]
  }.freeze

  WITHOUT_POLICY = [ CRUD_WITHOUT_POLICY, INTERVENTIONS_WITHOUT_POLICY ]
                   .flat_map { |table| table.flat_map { |c, actions| actions.map { |a| "#{c}##{a}" } } }.freeze

  # One real row per controller. A member route answering 404 never reached
  # the point where a policy would be asked, so its "no" would be a guess —
  # the example below refuses to record one.
  def record_id_for(controller)
    case controller
    when "admin/courier_wallets" then create(:user, :courier).courier_wallet.id
    when "admin/settings"
      key, definition = Setting::DEFINITIONS.first
      Setting.create!(key: key, value: definition[:default], value_type: definition[:type]).id
    when "admin/pricing_rates"
      PricingRate.create!(job_kind: "ride", audience: :customer, vehicle_type: :car, base: 40, per_km: 10).id
    when "admin/courier_shifts"
      CourierShift.create!(courier: create(:user, :courier), started_at: 1.hour.ago).id
    when "admin/merchant_statements"
      MerchantStatement.create!(merchant: create(:merchant), currency: "AFN", issued_at: Time.current,
                                period_start: 7.days.ago.to_date, period_end: Date.current).id
    else
      model = Administrate::ResourceResolver.new(controller).resource_class
      create(model.model_name.singular.to_sym).id
    end
  end

  # `send_action` runs only after the before-actions pass, so reaching it means
  # the request got past `authenticate_admin_user!` into the action itself —
  # a redirect to the login page cannot be mistaken for an answer.
  def consulted_a_policy?(route)
    reached = nil
    allow_any_instance_of(Admin::ApplicationController).to receive(:send_action).and_wrap_original do |original, *args|
      original.call(*args)
    ensure
      reached = original.receiver.send(:pundit_policy_authorized?)
    end

    path = route[:spec].include?(":id") ? route[:spec].sub(":id", record_id_for(route[:controller]).to_s) : route[:spec]
    # A create reads its params before `authorize_resource` in Administrate's
    # own order, so an empty body would 400 before a policy could be asked.
    body = route[:action] == "create" ? { Administrate::ResourceResolver.new(route[:controller]).resource_class.model_name.param_key => { probe: "1" } } : {}
    public_send(route[:verb], path, params: body)

    expect(reached).not_to be_nil, "#{route[:controller]}##{route[:action]} was never reached — the sweep has no answer for it"
    expect(response).not_to have_http_status(:not_found),
                            "#{route[:controller]}##{route[:action]} answered 404 — its record builder is wrong, so a policy was never reachable"
    reached
  end

  before do
    post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
  end

  it "found the whole console" do
    # A table-driven spec over an empty table is the vacuously-green suite this
    # project has been bitten by before.
    expect(CONSOLE_ACTIONS.size).to eq(114)
  end

  it "lists nothing that is not a route" do
    routed = CONSOLE_ACTIONS.map { |r| "#{r[:controller]}##{r[:action]}" }

    expect(WITHOUT_POLICY - routed).to be_empty
  end

  it "records 104 actions without a policy — the gap, counted" do
    expect(WITHOUT_POLICY.size).to eq(104)
  end

  CONSOLE_ACTIONS.each do |route|
    key = "#{route[:controller]}##{route[:action]}"

    it "#{key} #{WITHOUT_POLICY.include?(key) ? 'is recorded as consulting no policy' : 'consults a policy'}" do
      consulted = consulted_a_policy?(route)

      if WITHOUT_POLICY.include?(key)
        expect(consulted).to be(false), "#{key} now consults a policy — take it off WITHOUT_POLICY"
      else
        expect(consulted).to be(true), "#{key} consults no policy — add `authorize`, or list it with a reason"
      end
    end
  end
end
