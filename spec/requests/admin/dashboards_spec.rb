require "rails_helper"

# EVERY OPS PAGE ACTUALLY RENDERS.
#
# Administrate dashboards name their columns in a constant, which means a
# renamed column is not a compile error, not a failing model spec and not a
# failing request spec — it is a 500 the first time Hamma9900 opens that page,
# and this is the one surface with no second mechanism behind it. `docs/NOTES.md`
# records the general form of this trap: verify at the layer where it lands.
#
# It bit for real when `users.active_role` became `users.last_active_role`:
# 1078 examples stayed green and `/admin/users` would have died on its first
# request.
#
# So this walks every dashboard's index, and every show/edit page that exists,
# against one seeded row. It is a smoke test and it is meant to be: it catches
# the whole class of "the dashboard names a field the model no longer has" for
# every dashboard at once, including ones added later.
RSpec.describe "Every ops console page renders", type: :request do
  let(:admin) { AdminUser.create!(name: "Ops", email: "ops@karwan.af", password: "a-long-test-password") }

  before do
    post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
  end

  # One row per resource, built inside the example — a lambda defined at group
  # level closes over the GROUP, where `create` does not exist.
  def row_for(resource)
    case resource
    when "orders" then create(:order, :with_items)
    when "trips" then create(:trip)
    when "error_reports" then create(:error_report)
    when "merchants" then create(:merchant)
    when "courier_profiles" then create(:user, :courier).courier_profile
    when "courier_wallets" then create(:user, :courier).courier_wallet
    when "users" then create(:user, :courier)
    when "settings" then Setting.first || create(:setting)
    when "pricing_rates" then PricingRate.first || PricingRate.create!(job_kind: "ride", audience: :customer, vehicle_type: :car, base: 40, per_km: 10)
    when "audit_logs" then create(:audit_log)
    when "wallet_entries" then create(:wallet_entry)
    when "settlements" then create(:settlement)
    # A CLOSED shift, deliberately: an open one renders a blank `ended_at` and
    # would leave the show page's most interesting column untested.
    when "courier_shifts" then create(:user, :courier).courier_shifts.create!(started_at: 3.hours.ago,
                                                                             ended_at: 1.hour.ago)
    when "merchant_statements" then create(:merchant).statements.create!(
      period_start: 7.days.ago.to_date, period_end: 1.day.ago.to_date, currency: "AFN",
      orders_count: 3, items_total: 1_200, commission: 150, net_received: 1_050, issued_at: Time.current
    )
    when "merchant_opening_hours" then create(:merchant_opening_hour)
    when "catalog_categories" then create(:catalog_category)
    when "catalog_items" then create(:catalog_item)
    when "merchant_categories" then create(:merchant_category)
    when "catalog_item_options" then create(:catalog_item_option)
    when "catalog_item_option_values" then create(:catalog_item_option_value)
    else raise ArgumentError, "no row defined for #{resource}"
    end
  end

  # Mirrors `config/routes.rb` rather than guessing, so a read-only dashboard is
  # never asked for an edit form it does not have.
  RESOURCES = %w[
    orders trips merchants courier_profiles courier_wallets users
    settings pricing_rates audit_logs error_reports wallet_entries settlements
    courier_shifts merchant_statements
    merchant_opening_hours catalog_categories catalog_items merchant_categories
    catalog_item_options catalog_item_option_values
  ].freeze
  EDITABLE = %w[
    merchants courier_profiles courier_wallets users settings pricing_rates
    merchant_opening_hours catalog_categories catalog_items merchant_categories
    catalog_item_options catalog_item_option_values
  ].freeze

  # ── THE HAND-WRITTEN LIST MUST STILL MATCH THE ROUTER ────────────────────
  #
  # `RESOURCES` mirrors `config/routes.rb` deliberately, so a read-only
  # dashboard is never asked for an edit form it does not have. The cost of a
  # hand-written denominator is that it drifts silently, so this asserts it
  # against the router: a twelfth console resource turns this red rather than
  # quietly escaping every example below.
  it "lists exactly the resources the router exposes with index and show" do
    routed = Rails.application.routes.routes.filter_map { |route|
      controller = route.defaults[:controller]
      next unless controller&.start_with?("admin/")

      [ controller.sub("admin/", ""), route.defaults[:action] ]
    }.group_by(&:first)
     .select { |_c, pairs| (pairs.map(&:last) & %w[index show]).size == 2 }
     .keys

    expect(routed.sort).to eq(RESOURCES.sort)
  end

  it "renders the console root" do
    get "/admin"

    expect(response).to have_http_status(:ok)
  end

  RESOURCES.each do |resource|
    describe "/admin/#{resource}" do
      it "renders the index with a row in it" do
        row_for(resource)

        get "/admin/#{resource}"

        expect(response).to have_http_status(:ok)
      end

      it "renders the show page" do
        row = row_for(resource)

        get "/admin/#{resource}/#{row.id}"

        expect(response).to have_http_status(:ok)
      end

      # ── SEARCH, WHICH NOTHING DROVE UNTIL 2026-09-17 ──────────────────
      #
      # The thousand-times-a-day action — an operator with a code read out to
      # them over the phone — and it was the one console path with no coverage
      # at all. That is how a deprecation inside `Administrate::Search` sat
      # unseen: the suite emitted ZERO deprecation warnings, not because there
      # were none but because nothing exercised the code that emits them.
      #
      # A `COLLECTION_FILTERS` lambda against a renamed column, or a searchable
      # attribute that no longer exists, 500s here and nowhere else.
      it "answers a search without raising" do
        row_for(resource)

        get "/admin/#{resource}", params: { search: "kabab" }

        expect(response).to have_http_status(:ok), "searching #{resource} raised"
      end

      if EDITABLE.include?(resource)
        it "renders the edit form" do
          row = row_for(resource)

          get "/admin/#{resource}/#{row.id}/edit"

          expect(response).to have_http_status(:ok)
        end
      end
    end
  end

  # Not in the table above because it is not routed: `AdminUserDashboard`
  # exists for Administrate's own use, but there is no page for creating admins
  # from the browser. Listed here so that adding the route later also adds it
  # to the table above rather than shipping untested.
  it "does not route admin_users" do
    get "/admin/admin_users"

    expect(response).to have_http_status(:not_found)
  end

  # The merchant edit form, called out on its own because it 404'd for a reason
  # no other resource could hit: `config.api_only` makes a bare `resources`
  # omit `new` and `edit`, and merchants was the only one not spelling out its
  # actions. Editing a commission rate is an ops job, not a deploy.
  it "renders the form for creating a merchant" do
    get "/admin/merchants/new"

    expect(response).to have_http_status(:ok)
  end

  # ══ CAN A MESSAGE LEAVE THIS BOX AT ALL? ══════════════════════════════════
  #
  # `bin/preflight` answers this and only ever runs on a developer's machine.
  # Both channels fail SILENTLY by design — the log adapter writes the code
  # where a developer can read it, `FcmClient` logs "would notify" and returns
  # `:unconfigured` — so every screen stays green while nothing arrives.
  #
  # ENV IS SET DIRECTLY, not stubbed on the adapters. The adapters are what the
  # app really consults, so doubling them would put a double between this check
  # and the thing it is checking; the environment is the outside world, which
  # `docs/NOTES.md` names as the legitimate place for a test to take control.
  # Same idiom as `spec/services/notifications/sms_client_spec.rb`.
  describe "channels that cannot deliver" do
    around do |example|
      kept = ENV.to_h.slice("SMS_PROVIDER", "FCM_PROJECT_ID", "FCM_ACCESS_TOKEN")
      example.run
      %w[SMS_PROVIDER FCM_PROJECT_ID FCM_ACCESS_TOKEN].each { |key| ENV.delete(key) }
      kept.each { |key, value| ENV[key] = value }
    end

    def configure_everything
      ENV["SMS_PROVIDER"] = "kabul_gateway"
      ENV["FCM_PROJECT_ID"] = "karwan"
      ENV["FCM_ACCESS_TOKEN"] = "a-token"
    end

    it "says nothing when both channels can deliver" do
      configure_everything

      get "/admin"

      expect(response.body).not_to include("not configured on this server")
    end

    # THE ONE THAT LOCKS PEOPLE OUT. Correction 2 made email the ADDITIONAL
    # identifier, so a user with only a phone and a forgotten password has no
    # way back in at all when SMS is dead.
    it "names what a dead SMS channel costs" do
      configure_everything
      ENV["SMS_PROVIDER"] = "log"

      get "/admin"

      expect(response.body).to include("not configured on this server")
      expect(response.body).to include("cannot get back into their account")
    end

    # And push is a DEGRADATION, not a lockout — PRODUCT.md refuses to rely on
    # any single channel for the merchant alert. Saying the same thing about
    # both would teach the operator to treat the worse one as routine.
    it "does not claim a dead push channel locks anybody out" do
      configure_everything
      ENV.delete("FCM_PROJECT_ID")

      get "/admin"

      expect(response.body).to include("not configured on this server")
      expect(response.body).to include("three channels")
      expect(response.body).not_to include("cannot get back into their account")
    end

    # ── ASKED OF THE ADAPTER, NOT OF ENV ─────────────────────────────────
    #
    # A SECOND non-production adapter is the only way this example can tell the
    # adapter's rule from a copy of it. Written first with
    # `NON_PRODUCTION.first`, it could not: the list has one entry, so a
    # controller comparing `ENV["SMS_PROVIDER"] == "log"` agrees with the rule
    # for every input. Planting exactly that left this green — found by
    # planting, not by reading.
    #
    # `stub_const` arranges the world rather than doubling the subject: the
    # thing under test is the dashboard, and this is the configuration it reads.
    it "follows the adapter's own rule rather than a second copy of it" do
      configure_everything
      stub_const("Notifications::SmsClient::NON_PRODUCTION", %w[log noop])
      ENV["SMS_PROVIDER"] = "noop"

      get "/admin"

      expect(Notifications::SmsClient.production_ready?).to be(false), "plant a provider the app calls dead"
      expect(response.body).to include("not configured on this server"),
                               "the dashboard holds its own copy of the rule and missed a second dead adapter"
    end
  end
end
