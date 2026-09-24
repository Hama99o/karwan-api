require "rails_helper"

# The console's detour report: which REAL orders a ratio would have touched,
# from what each order already recorded. It measures; it decides nothing, and
# re-prices nothing. See `Routing::Detours`.
RSpec.describe "roads far longer than the straight line", type: :request do
  let(:admin) { AdminUser.create!(name: "Ops", email: "ops@karwan.af", password: "a-long-test-password") }
  let(:merchant) { create(:merchant, latitude: 34.5323, longitude: 69.2294) }

  # The measured worst realistic pair: 2.36 km apart by Geo::Distance at these
  # four-decimal pins, 15.78 km by road.
  let!(:looped) do
    create(:order, merchant: merchant, delivery_latitude: 34.5290, delivery_longitude: 69.2548,
                   distance_km: 15.78, distance_source: "osrm", delivery_fee: 366)
  end
  # An ordinary one: 1.4x.
  let!(:ordinary) do
    create(:order, merchant: merchant, delivery_latitude: 34.5290, delivery_longitude: 69.2548,
                   distance_km: 3.3, distance_source: "osrm", delivery_fee: 116)
  end
  # Priced on a straight line: its ratio is 1 by definition, so it is not measured.
  let!(:straight) do
    create(:order, merchant: merchant, delivery_latitude: 34.5290, delivery_longitude: 69.2548,
                   distance_km: 2.35, distance_source: "straight_line", delivery_fee: 97)
  end

  before do
    post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
  end

  let(:page) { Nokogiri::HTML(response.body) }
  let(:section_rows) do
    table = page.xpath("//h2[starts-with(normalize-space(), 'Roads far longer')]/following-sibling::table[1]")
    table.css("tbody tr").map { |tr| tr.css("td").map { |td| td.text.strip } }
  end

  it "lists the order past the ratio, with both distances and the fee it was charged" do
    get "/admin/reports"

    expect(section_rows.size).to eq(1)
    expect(section_rows.first).to eq([ looped.code, "2.36 km", "15.78 km", "6.7x", "366.0 AFN" ])
  end

  it "says how many of how many road-priced orders, so a count can be read against its base" do
    get "/admin/reports"

    expect(response.body).to include("<strong>1</strong> of 2 road-priced orders")
  end

  it "takes the ratio from the page, so he can see what another cap would touch" do
    get "/admin/reports", params: { detour_ratio: "1.2" }

    expect(section_rows.map(&:first)).to eq([ looped.code, ordinary.code ])
  end

  it "re-prices nothing" do
    expect { get "/admin/reports", params: { detour_ratio: "1.2" } }
      .not_to(change { Order.pluck(:delivery_fee, :distance_km) })
  end
end
