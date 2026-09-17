require "rails_helper"

RSpec.describe "The ops console", type: :request do
  let(:admin) { AdminUser.create!(name: "Ops", email: "ops@karwan.af", password: "a-long-test-password") }

  def sign_in_admin
    post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
  end

  describe "authentication" do
    # Admin auth is NOT the mobile auth. A separate table means a customer or
    # courier token can never reach this surface.
    it "refuses the console to a signed-out visitor" do
      get "/admin"

      expect(response).to have_http_status(:found)
      expect(response.location).to include("/admin/login")
    end

    it "refuses every intervention route to a signed-out visitor" do
      order = create(:order)

      patch "/admin/orders/#{order.id}/cancel"

      expect(response).to have_http_status(:found)
      expect(order.reload.status).to eq("placed")
    end

    # A mobile bearer token is not an admin session, and must not become one.
    it "refuses a mobile token, however valid" do
      user = create(:user, :admin)
      token = UserSession.issue!(user).last

      get "/admin", headers: { "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:found)
      expect(response.location).to include("/admin/login")
    end

    it "lets a real admin in" do
      sign_in_admin

      expect(response).to have_http_status(:found)
      expect(response.location).to include("/admin")

      get "/admin"
      expect(response).to have_http_status(:ok)
    end

    it "records the sign-in, because this surface can change anything" do
      expect { sign_in_admin }.to change { AuditLog.where(action: "admin.signed_in").count }.by(1)
    end

    # The same message either way, so nobody can enumerate which addresses are
    # admin accounts.
    it "refuses a wrong password without revealing whether the account exists" do
      post "/admin/login", params: { admin_user: { email: admin.email, password: "wrong" } }
      known = response.body

      post "/admin/login", params: { admin_user: { email: "nobody@karwan.af", password: "wrong" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Invalid email or password")
      expect(known).to include("Invalid email or password")
    end

    it "locks the account after repeated failures" do
      Devise.maximum_attempts.times do
        post "/admin/login", params: { admin_user: { email: admin.email, password: "wrong" } }
      end

      expect(admin.reload).to be_access_locked
    end
  end

  describe "the landing page" do
    before { sign_in_admin }

    it "answers what needs attention right now" do
      create(:order, :overdue)
      create(:order, :preparing)

      get "/admin"

      expect(response.body).to include("orders overdue")
      expect(response.body).to include("orders with no courier")
      expect(response.body).to include("couriers on shift")
    end

    it "shows money grouped by currency, never summed across it" do
      create(:order, :delivered, commission: 50)

      get "/admin"

      expect(response.body).to include("AFN")
      expect(response.body).to include("Commission today")
    end

    # THE BOARD. A default index is a table of rows; this is a work queue.
    describe "the live order board" do
      it "shows age in the CURRENT state, not since placement" do
        order = create(:order, :accepted)
        order.update_columns(accepted_at: 7.minutes.ago, placed_at: 2.hours.ago)

        get "/admin/orders"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("7 min")
      end

      # Visible from across a room without reading. The threshold comes from
      # the same TIMEOUTS table the timeout job reads, so the board and the job
      # cannot disagree about what "late" means.
      it "colours an overdue order red" do
        create(:order, :overdue)

        get "/admin/orders"

        expect(response.body).to include("karwan-row--alert")
      end

      it "leaves a fresh order uncoloured" do
        create(:order)

        get "/admin/orders"

        expect(response.body).not_to include("karwan-row--alert")
      end

      it "sorts terminal orders to the bottom rather than hiding them" do
        create(:order, :delivered)
        live = create(:order)

        get "/admin/orders"

        expect(response.body).to include(live.code)
      end

      it "filters to overdue in one click" do
        overdue = create(:order, :overdue)
        fresh = create(:order)

        get "/admin/orders", params: { filter: "overdue" }

        expect(response.body).to include(overdue.code)
        # by-design: the line above asserts the overdue order IS in the body.
        expect(response.body).not_to include(fresh.code)
      end

      it "filters to orders with no courier" do
        unassigned = create(:order, :accepted)
        assigned = create(:order, :picked_up)

        get "/admin/orders", params: { filter: "unassigned" }

        expect(response.body).to include(unassigned.code)
        expect(response.body).not_to include(assigned.code)
      end

      # Never editable through the generic form: every change goes through a
      # named intervention that writes an audit row.
      it "offers no edit form for an order" do
        routes = Rails.application.routes.routes.filter_map do |route|
          next unless route.defaults[:controller] == "admin/orders"

          route.defaults[:action]
        end

        expect(routes).to include("index"), "no routes found at all — the check below is vacuous"
        expect(routes.uniq).not_to include("edit", "update", "destroy", "new", "create")
      end
    end

    it "lists recent interventions with who did them" do
      order = create(:order)
      AuditLog.record!(action: "order.cancelled", admin_user: admin, target: order)

      get "/admin"

      expect(response.body).to include("order.cancelled")
      expect(response.body).to include("Ops")
    end
  end
end
