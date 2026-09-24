require "rails_helper"

# Two attempts that land together — the app's retry fires while the first is
# still in flight. Both find no order under the key; the unique index lets one
# insert, and the other must be answered with it rather than fail.
#
# Real threads, each its own integration session, on a committed database; a
# gate holds both inside "place" until the other arrives, or a second passes.
RSpec.describe "placing an order at most once, at the same moment", type: :request do
  self.use_transactional_tests = false
  after { DatabaseCleaner.clean_with(:truncation) }

  let(:customer) { create(:user, :customer) }
  let(:merchant) { create(:merchant, latitude: 34.5553, longitude: 69.2075, commission_rate: 0.125) }
  let!(:kabab) { create(:catalog_item, catalog_category: create(:catalog_category, merchant: merchant), price: 400) }

  it "places one order and answers both attempts with it" do
    arrived = Queue.new
    gate = Module.new do
      define_method(:call) do
        arrived << 1
        deadline = Time.current + 1
        sleep 0.01 until arrived.size >= 2 || Time.current > deadline
        super()
      end
    end
    Orders::PlaceService.prepend(gate)

    headers = { "Authorization" => "Bearer #{UserSession.issue!(customer).last}",
                "Idempotency-Key" => "5f0c7b1e-3a2d-4c8e-9b1f-7d6e5a4c3b2a" }
    body = { order: { merchant_id: merchant.id, delivery_latitude: "34.5400", delivery_longitude: "69.1750",
                      lines: [ { catalog_item_id: kabab.id, quantity: 1 } ] } }

    # Rails draws routes on the first request, and two first requests in
    # parallel race that: one got "No route matches" while writing this. Warm
    # them here, so the threads only race each other.
    get "/api/v1/customer/orders", headers: headers.except("Idempotency-Key")

    answers = 2.times.map do
      Thread.new do
        session = open_session
        session.post "/api/v1/customer/orders", params: body, headers: headers
        [ session.response.status, JSON.parse(session.response.body).dig("order", "code") ]
      end
    end.map(&:value)

    expect(Order.count).to eq(1)
    expect(answers.map(&:first)).to eq([ 201, 201 ])
    expect(answers.map(&:last).uniq).to eq([ Order.last.code ])
  end
end
