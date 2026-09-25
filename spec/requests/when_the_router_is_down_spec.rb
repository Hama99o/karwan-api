require "rails_helper"

# WHEN THE ROUTER IS DOWN, EVERY FARE IS QUIETLY 15-20% LOW.
#
# DistanceResolver falls back to the straight line when OSRM cannot be
# reached. That is the right thing to do (an order must still place), and
# until 25 Sept 2026 nothing in the suite ever made the router fail, and
# nothing counted how often it had. The one trace was a warn line in a log
# nobody tails. In dev, every order placed through the real path had fallen
# back, and nobody knew.
#
# So this drives the real placement with the router failing, and asserts both
# halves: the order RECORDS that it was priced by straight line, and the
# reports page COUNTS it. If either stops being true, an outage is invisible
# again, and the aggregate would even say "all road".
RSpec.describe "When the router is down", type: :request do
  let(:customer) { create(:user, :customer) }
  let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(customer).last}" } }
  let(:merchant) { create(:merchant, latitude: 34.5553, longitude: 69.2075) }
  let!(:kabab) { create(:catalog_item, catalog_category: create(:catalog_category, merchant: merchant), price: 400) }
  let(:osrm) { %r{karwan_osrm:5000/route/v1/driving/} }
  let(:recorded) { Rails.root.join("spec/fixtures/files/osrm_kabul_route.json").read }

  # The production default; specs otherwise opt out (spec/support/routing_default.rb).
  before do
    Setting.seed_defaults!
    Setting.find_by!(key: "routing_distance_source").update!(value: "osrm")
  end

  def place
    post "/api/v1/customer/orders",
         params: { order: { merchant_id: merchant.id, delivery_latitude: 34.5401, delivery_longitude: 69.1751,
                            lines: [ { catalog_item_id: kabab.id, quantity: 1 } ] } },
         headers: auth
    expect(response).to have_http_status(:created), response.body
    Order.order(:id).last
  end

  it "still places the order, and records that it was priced by straight line" do
    stub_request(:get, osrm).to_timeout

    order = place

    expect(order.distance_source).to eq("straight_line")
  end

  it "records road when the router answers, so the two are told apart" do
    stub_request(:get, osrm).to_return(status: 200, body: recorded)

    expect(place.distance_source).to eq("osrm")
  end

  it "is counted, so an outage shows on the reports page" do
    stub_request(:get, osrm).to_return(status: 200, body: recorded)
    place
    WebMock.reset!
    stub_request(:get, osrm).to_return(status: 503)
    2.times { place }

    counts = Routing::DistanceSources.new.counts["Deliveries"]

    expect(counts[:window]).to include("osrm" => 1, "straight_line" => 2)
    expect(counts[:today]).to include("osrm" => 1, "straight_line" => 2)
    expect(Routing::DistanceSources.new.straight_line_share("Deliveries")).to eq(66.7)
  end

  # A row that never went through a quote is not "road".
  it "shows an unrecorded row as unrecorded, never as either method" do
    create(:order, merchant: merchant, distance_source: nil)

    expect(Routing::DistanceSources.new.counts["Deliveries"][:window]).to include("unrecorded" => 1, "osrm" => 0)
  end

  it "puts the count on the console's reports page" do
    stub_request(:get, osrm).to_timeout
    place
    admin = AdminUser.create!(name: "Najibullah", email: "ops@karwan.af", password: "a-long-test-password")
    post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }

    get "/admin/reports"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Priced by road, or by straight line")
    expect(response.body).to include("100.0%")
  end
end
