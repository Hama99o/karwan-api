require "rails_helper"

# The shop page lists the week's hours. Marking "today" from the phone's
# clock would mark the wrong day whenever the phone's date isn't Kabul's, so
# the server says which day it is at the shop.
RSpec.describe "The shop's own today", type: :request do
  let(:merchant) { create(:merchant) }

  def today_at_the_shop
    get "/api/v1/public/merchants/#{merchant.id}"
    expect(response).to have_http_status(:ok), response.body[0, 200]
    JSON.parse(response.body).dig("merchant", "today_day_of_week")
  end

  it "is Kabul's day, not UTC's" do
    # Thursday 21:00 UTC is Friday 01:30 in Kabul.
    travel_to(Time.utc(2026, 9, 24, 21, 0)) { expect(today_at_the_shop).to eq(5) }
  end

  # Early morning in Kabul is still the same date in Paris (this box) but
  # the day before in New York, so a process-clock bug hides here on the
  # box and shows under bin/rspec-in-another-zone.
  it "is Kabul's day at 03:00 in Kabul, which is yesterday in New York" do
    travel_to(Time.utc(2026, 9, 21, 22, 30)) { expect(today_at_the_shop).to eq(2) } # Tuesday in Kabul
  end

  it "numbers days the way the opening-hours rows do (0 = Sunday)" do
    travel_to(Time.utc(2026, 9, 27, 8, 0)) { expect(today_at_the_shop).to eq(0) }
  end
end
