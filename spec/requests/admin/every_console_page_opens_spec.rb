require "rails_helper"

# ═══ DOES EVERY CONSOLE PAGE ACTUALLY OPEN? ════════════════════════════════
#
# The floor for a surface five to ten people will live in, and nothing asserted
# it. The 18 custom actions are proven to audit and the data model is proven
# safe — but **nothing drove the ordinary pages**, which is exactly why
# Administrate's search was dark until an operator spec happened to exercise it
# and printed a deprecation nobody knew about.
#
# A dashboard naming a column that was dropped, a `display_resource` calling a
# removed method, or a `COLLECTION_FILTERS` lambda against a renamed field
# **500s the moment somebody opens it**, and today nothing would say so.
#
# ── DERIVED FROM THE ROUTER, WITH A FIXTURE PER RESOURCE ─────────────────
#
# `CONSOLE_RESOURCES` is asked of `Rails.application.routes`, so resource 12 is covered
# the day it is added. And every show page is driven against a REAL RECORD:
# an empty table would render an empty page and give a vacuous green across
# every dashboard at once — the fifth shape at scale, which is the failure this
# file would most easily become.
RSpec.describe "every console page opens", type: :request do
  let(:admin) do
    AdminUser.create!(name: "Najibullah", email: "ops@karwan.af", password: "a-long-test-password")
  end

  before do
    post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
  end

  # Resources with BOTH index and show, asked of the router.
  #
  # NAMED UNIQUELY, and that is not style. **A constant assigned inside an
  # `RSpec.describe` block is defined on `Object`** — it is top-level, not
  # scoped to the example group. `spec/requests/admin/every_intervention_is_audited_spec.rb`
  # also defines `ROUTED`, so both files passed alone and collided the moment a
  # suite loaded them together: whichever loaded second won, and the other
  # file's examples ran against a list meant for a different question.
  #
  # Exactly the shape of the shared test database — green in isolation, wrong
  # together — and invisible unless the whole suite runs.
  CONSOLE_RESOURCES = Rails.application.routes.routes.filter_map { |route|
    controller = route.defaults[:controller]
    next unless controller&.start_with?("admin/")

    [ controller.sub("admin/", ""), route.defaults[:action] ]
  }.group_by(&:first)
   .select { |_c, pairs| (pairs.map(&:last) & %w[index show]).size == 2 }
   .keys.sort.freeze

  # One real row per resource. `pricing_rates` has no factory — its rows come
  # from `PricingRate.seed_defaults!`, which is how they arrive in production
  # too, so that is the honest fixture for it.
  def fixture_for(resource)
    case resource
    when "audit_logs"        then create(:audit_log)
    when "courier_profiles"  then create(:courier_profile)
    when "courier_wallets"   then create(:courier_wallet)
    when "merchants"         then create(:merchant)
    when "orders"            then create(:order, :with_items)
    when "pricing_rates"     then PricingRate.seed_defaults! && PricingRate.first
    when "settings"          then create(:setting)
    when "settlements"       then create(:settlement)
    when "trips"             then create(:trip)
    when "users"             then create(:user)
    when "wallet_entries"    then create(:wallet_entry)
    end
  end

  # ── ANTI-DRIFT ───────────────────────────────────────────────────────────
  #
  # The router is the denominator. A resource added without a fixture here
  # turns this red rather than quietly escaping the floor.
  it "has a fixture for every routed console resource" do
    missing = CONSOLE_RESOURCES.reject { |resource| fixture_for(resource).present? }

    expect(missing).to be_empty,
                       "no fixture for: #{missing.join(', ')} — these pages are not being driven"
  end

  it "covers a plausible number of resources" do
    expect(CONSOLE_RESOURCES.size).to be >= 10
    expect(CONSOLE_RESOURCES).to include("orders", "users", "merchants", "courier_wallets")
  end

  # The landing page, which is the first thing anybody sees.
  it "opens the console root" do
    get "/admin"

    expect(response).to have_http_status(:ok)
  end

  CONSOLE_RESOURCES.each do |resource|
    context "/admin/#{resource}" do
      it "opens the index" do
        fixture_for(resource)

        get "/admin/#{resource}"

        expect(response).to have_http_status(:ok), "the #{resource} index did not render"
      end

      # THE PATH THAT WAS DARK. Console search is the thousand-times-a-day
      # action and nothing drove it until today — which is how a deprecation
      # inside `Administrate::Search` went unseen.
      it "answers a search without raising" do
        fixture_for(resource)

        get "/admin/#{resource}", params: { search: "kabab" }

        expect(response).to have_http_status(:ok), "searching #{resource} raised"
      end

      # Driven against a REAL record. Asserted present first, because an empty
      # table renders a page that proves nothing.
      it "opens a show page for a real record" do
        record = fixture_for(resource)

        expect(record).to be_present, "no fixture — the assertion below would be vacuous"

        get "/admin/#{resource}/#{record.id}"

        expect(response).to have_http_status(:ok), "the #{resource} show page did not render"
      end
    end
  end

  # ── THE UNROUTED DASHBOARDS ARE NOT DEAD ─────────────────────────────────
  #
  # Ten dashboards have no route of their own — `order_item`, `status_transition`,
  # `user_role` and the rest. They are not unreachable: Administrate renders
  # associations through them, so a broken one 500s its PARENT page rather than
  # its own. Driving an order's show page with items and transitions on it is
  # what covers them, and this says so out loud so nobody deletes them as unused.
  it "renders an order whose associations are drawn by unrouted dashboards" do
    order = create(:order, :with_items, :ready)
    order.transitions.create!(to_status: "accepted", actor_role: :merchant_owner)

    get "/admin/orders/#{order.id}"

    expect(response).to have_http_status(:ok)
    expect(order.order_items).to be_present, "no items — the association was not exercised"
    expect(order.transitions).to be_present, "no transitions — the association was not exercised"
  end
end
