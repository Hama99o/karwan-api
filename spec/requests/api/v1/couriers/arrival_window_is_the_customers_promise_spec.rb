require "rails_helper"

# THE COURIER MUST SEE THE PROMISE MADE ON HIS BEHALF.
#
# `arrival_window` was on the customer's order and track payloads and on nothing
# the courier could see, so the customer read "۱۳:۳۰ – ۱۳:۴۰" and the one man
# whose movements make that true or false had never been told it was said.
#
# It is not an estimate FOR him — he judges his own arrival better than this
# arithmetic does. It is the expectation he is measured against, by the customer
# on the phone and by whoever reviews a late delivery afterwards.
RSpec.describe "A courier sees the arrival window the customer was promised", type: :request do
  def json = JSON.parse(response.body)

  let(:courier) { create(:user, :courier) }
  let(:courier_auth) { { "Authorization" => "Bearer #{UserSession.issue!(courier).last}" } }
  let(:merchant) { create(:merchant, latitude: 34.5553, longitude: 69.2075) }

  before do
    courier.courier_profile.update!(is_available: true, accepted_job_kinds: %w[delivery ride],
                                    last_latitude: 34.5553, last_longitude: 69.2075,
                                    location_updated_at: Time.current)
    courier.courier_wallet.update!(balance: 5_000, credit_line: 500)
  end

  def delivery
    order = create(:order, :with_items, :ready, merchant: merchant, courier: courier,
                                                items_total: 400, delivery_fee: 100,
                                                customer_total: 500, commission: 50,
                                                courier_fee: 100, merchant_payout: 350,
                                                # Set explicitly: the factory leaves it nil, and
                                                # `ArrivalWindow` correctly returns nil for an order
                                                # whose distance was never measured. A real order
                                                # carries it, frozen at quote time.
                                                distance_km: 3.5)
    %w[accepted preparing ready].each do |reached|
      order.transitions.create!(to_status: reached, actor_role: :merchant_owner, created_at: Time.current)
    end
    order
  end

  # THE CLOCK IS FROZEN for the whole example. Both payloads compute the window
  # from `Time.current`, so a second ticking between the two requests could move
  # one and not the other and turn a real agreement into a flake — or, worse,
  # hide a real disagreement behind a rounding boundary.
  it "shows the courier EXACTLY what the customer is shown, not a second computation of it" do
    travel_to Time.zone.parse("2026-09-19 13:00:00 +0430") do
      order = delivery

      get "/api/v1/courier/job", headers: courier_auth
      courier_window = json.dig("job", "arrival_window")

      customer_auth = { "Authorization" => "Bearer #{UserSession.issue!(order.customer).last}" }
      get "/api/v1/customer/orders/#{order.id}/track", headers: customer_auth
      customer_window = json.dig("track", "arrival_window") || json.dig("order", "arrival_window")

      # ASSERTED FIRST, AND NOT AS DECORATION. If both payloads returned nil the
      # equality below would pass while proving nothing — nil == nil is the
      # vacuous green this whole exercise exists to refuse.
      expect(courier_window).not_to be_nil,
                                    "the courier's window is nil, so the comparison below cannot fail"
      expect(customer_window).not_to be_nil,
                                     "the customer's window is nil, so there is no promise to match"

      expect(courier_window).to eq(customer_window)
    end
  end

  # A ride has no kitchen, no merchant and no `picked_up_at`, and no
  # customer-facing ride payload carries a window — so there is no promise to
  # relay. Nil is the honest answer; the point of this example is that asking
  # must not RAISE, which it would if the guard were removed.
  it "is nil for a ride rather than raising, because no ride promise exists" do
    trip = create(:trip, :accepted, courier: courier)

    get "/api/v1/courier/job", headers: courier_auth

    expect(response).to have_http_status(:ok)
    expect(json.dig("job", "id")).to eq(trip.id)
    expect(json.dig("job", "arrival_window")).to be_nil
  end
end
