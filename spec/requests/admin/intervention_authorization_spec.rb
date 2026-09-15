require "rails_helper"

# EVERY intervention route, checked against EVERY way of not being an admin.
#
# Written as a table rather than as one example per endpoint, deliberately. The
# previous coverage tested `cancel` reachable-while-signed-out and left the
# other seventeen to inference — and an intervention endpoint reachable without
# an admin session is the worst bug available in this app. A table also means a
# route added later without auth shows up here rather than in production,
# because the list is derived from the ROUTE TABLE and not hand-maintained.
RSpec.describe "Admin interventions require an admin session", type: :request do
  # Derived from the routes, so a new intervention cannot be added without
  # appearing in this spec.
  INTERVENTION_ROUTES = Rails.application.routes.routes.filter_map do |route|
    controller = route.defaults[:controller]
    action = route.defaults[:action]
    next unless controller&.start_with?("admin/")
    # The generic CRUD reads are covered by the console spec; these are the
    # actions that change money, state or access.
    next if %w[index show new edit].include?(action)
    next if controller == "admin/sessions"

    verb = route.verb.is_a?(String) ? route.verb : route.verb.source.gsub(/[$^]/, "")
    { controller: controller, action: action, verb: verb.downcase.to_sym,
      spec: route.path.spec.to_s.sub("(.:format)", "") }
  end.uniq { |r| [ r[:controller], r[:action] ] }

  def path_for(route, id)
    route[:spec].gsub(":id", id.to_s)
  end

  # One real record per controller, so the request reaches authorization rather
  # than dying on a missing row.
  def subject_id_for(controller)
    case controller
    when "admin/orders" then create(:order).id
    when "admin/merchants" then create(:merchant).id
    when "admin/courier_profiles" then create(:courier_profile).id
    when "admin/courier_wallets" then create(:user, :courier).courier_wallet.id
    when "admin/users" then create(:user).id
    when "admin/settings" then Setting.create!(key: "x", value: "1", value_type: :integer).id
    else create(:order).id
    end
  end

  it "found every intervention route to check" do
    # A guard against the derivation silently matching nothing — a table-driven
    # spec over an empty table is the vacuously-green suite this project has
    # already been bitten by four times.
    expect(INTERVENTION_ROUTES.size).to be >= 15
  end

  INTERVENTION_ROUTES.each do |route|
    describe "#{route[:verb].to_s.upcase} #{route[:spec]}" do
      let(:id) { subject_id_for(route[:controller]) }

      it "redirects a signed-out visitor to the login page and changes nothing" do
        expect {
          public_send(route[:verb], path_for(route, id))
        }.not_to change { AuditLog.count }

        expect(response).to have_http_status(:found)
        expect(response.location).to include("/admin/login")
      end

      # A mobile bearer token is not an admin session and must never become
      # one — not even for a user who genuinely holds the admin ROLE. The two
      # surfaces share no auth code, and this is the assertion that proves it.
      it "refuses a mobile token from a user holding the admin role" do
        user = create(:user, :admin)
        token = UserSession.issue!(user).last

        public_send(route[:verb], path_for(route, id),
                    headers: { "Authorization" => "Bearer #{token}" })

        expect(response).to have_http_status(:found)
        expect(response.location).to include("/admin/login")
      end

      it "refuses a courier's token" do
        courier = create(:user, :courier)
        token = UserSession.issue!(courier).last

        public_send(route[:verb], path_for(route, id),
                    headers: { "Authorization" => "Bearer #{token}" })

        expect(response).to have_http_status(:found)
      end

      # A locked admin is not an admin. Devise refuses the login, so the
      # session never exists — but the route must still refuse rather than
      # relying on that.
      it "refuses a locked admin account" do
        admin = AdminUser.create!(name: "Locked", email: "locked@karwan.af",
                                  password: "a-long-test-password")
        post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
        admin.lock_access!

        public_send(route[:verb], path_for(route, id))

        expect(response).to have_http_status(:found)
        expect(response.location).to include("/admin/login")
      end
    end
  end

  describe "the console itself" do
    it "refuses every read screen to a signed-out visitor" do
      %w[/admin /admin/orders /admin/trips /admin/merchants /admin/courier_profiles
         /admin/courier_wallets /admin/users /admin/settings /admin/audit_logs
         /admin/wallet_entries /admin/settlements].each do |path|
        get path

        expect(response).to have_http_status(:found), "#{path} was reachable"
        expect(response.location).to include("/admin/login")
      end
    end
  end
end
