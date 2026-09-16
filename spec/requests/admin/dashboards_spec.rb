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
    when "merchants" then create(:merchant)
    when "courier_profiles" then create(:user, :courier).courier_profile
    when "courier_wallets" then create(:user, :courier).courier_wallet
    when "users" then create(:user, :courier)
    when "settings" then Setting.first || create(:setting)
    when "audit_logs" then create(:audit_log)
    when "wallet_entries" then create(:wallet_entry)
    when "settlements" then create(:settlement)
    else raise ArgumentError, "no row defined for #{resource}"
    end
  end

  # Mirrors `config/routes.rb` rather than guessing, so a read-only dashboard is
  # never asked for an edit form it does not have.
  RESOURCES = %w[
    orders trips merchants courier_profiles courier_wallets users
    settings audit_logs wallet_entries settlements
  ].freeze
  EDITABLE = %w[merchants courier_profiles courier_wallets users settings].freeze

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
end
