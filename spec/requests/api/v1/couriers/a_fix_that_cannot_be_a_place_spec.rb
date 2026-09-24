require "rails_helper"

# ── A POSITION NOBODY CAN BE AT IS NOT RECORDED ─────────────────────────────
#
# Found 2026-09-24: `POST /courier/shift/location` stored anything. "abc" was
# cast to 0 and stored as (0, 0); (999, 999) was stored; each was stamped
# FRESH over the courier's last real position. Dispatch was saved only by the
# offer radius. The customer's tracking map and the transition log's "where
# the courier was" — the evidence a delivery dispute is settled from — were
# not.
RSpec.describe "a fix that cannot be a place", type: :request do
  def json
    JSON.parse(response.body)
  end

  let(:courier) { create(:user, :courier) }
  let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(courier).last}" } }
  let(:profile) { courier.courier_profile }

  def report(latitude, longitude)
    post "/api/v1/courier/shift/location", params: { latitude: latitude, longitude: longitude }, headers: auth
  end

  before do
    profile.update!(last_latitude: 34.5553, last_longitude: 69.2075, location_updated_at: 10.minutes.ago)
  end

  {
    "text" => %w[abc def],
    "null island — a device with no fix" => %w[0 0],
    "a latitude off the planet" => %w[999 69.2],
    "a longitude off the planet" => %w[34.5 -181],
    "exponent notation off the planet" => %w[1e3 -1e3],
    "not a number" => %w[NaN 69.2]
  }.each do |what, (lat, lng)|
    describe "#{what} (#{lat}, #{lng})" do
      before { report(lat, lng) }

      it "is refused with a reason" do
        expect(response).to have_http_status(:unprocessable_content)
        expect(json["code"]).to eq("invalid_location")
      end

      it "leaves the last real position where it was" do
        expect([ profile.reload.last_latitude, profile.last_longitude ]).to eq([ 34.5553.to_d, 69.2075.to_d ])
      end

      # The dispatch-safety half: a broken phone must not make a stale courier
      # look current. Ten minutes old before, ten minutes old after.
      it "does not make a stale position look fresh" do
        expect(profile.reload.location_fresh?).to be(false)
      end
    end
  end

  it "records a real fix, and marks it fresh" do
    report("34.5400", "69.1750")

    expect(response).to have_http_status(:ok)
    expect([ profile.reload.last_latitude, profile.last_longitude ]).to eq([ 34.54.to_d, 69.175.to_d ])
    expect(profile.location_fresh?).to be(true)
  end

  # Somewhere real, if not where we work: a courier on his way home across the
  # city line. Refusing it would be a dispatch decision made in the wrong place.
  it "records a real place outside the service area" do
    report("36.7", "67.1")

    expect(response).to have_http_status(:ok)
  end
end
