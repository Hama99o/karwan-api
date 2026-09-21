require "rails_helper"

# ── A SHOP CORRECTING ITSELF ───────────────────────────────────────────────
#
# `GET merchant/profile` existed and nothing wrote it, so changing a phone
# number meant ringing an operator. `docs/NOTES.md` carried it as open.
#
# `prep_time_minutes` is the field that earns the endpoint: it feeds
# `Orders::ArrivalWindow`, so it is the number behind the range the CUSTOMER is
# shown. Only the kitchen knows it is slammed tonight.
RSpec.describe "A merchant corrects its own profile", type: :request do
  def json = JSON.parse(response.body)

  let(:owner) { create(:user, :merchant_owner) }
  let(:merchant) { create(:merchant, owner: owner, prep_time_minutes: 15, phone: "+93700000111") }
  let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(owner).last}" } }

  before { merchant }

  it "changes the fields a shop owns" do
    patch "/api/v1/merchant/profile",
          params: { merchant: { prep_time_minutes: 40, phone: "+93700000222",
                                landmark_note: "beside the blue gate" } },
          headers: auth, as: :json

    expect(response).to have_http_status(:ok)
    expect(merchant.reload.prep_time_minutes).to eq(40)
    expect(merchant.phone).to eq("+93700000222")
    expect(merchant.landmark_note).to eq("beside the blue gate")
  end

  # ── THE POINT OF THE ENDPOINT, ASSERTED END TO END ──────────────────────
  #
  # Not "the column changed" but "the customer is told something different".
  # A version that wrote the column and left the ETA reading the old value
  # would pass a column-level test and fail the only thing that matters.
  it "moves the arrival window the customer is shown" do
    customer = create(:user, :customer)
    order = create(:order, :with_items, :accepted, merchant: merchant, customer: customer,
                                                   distance_km: 3.0)
    before_window = Orders::ArrivalWindow.for(order)

    patch "/api/v1/merchant/profile",
          params: { merchant: { prep_time_minutes: 75 } }, headers: auth, as: :json

    after_window = Orders::ArrivalWindow.for(order.reload)

    expect(before_window).to be_present, "no window to compare — the test proves nothing"
    expect(after_window.to).to be > before_window.to,
                               "the kitchen said it needs an hour more and the customer was told the same range"
  end

  # ── THE PIN IS MONEY ───────────────────────────────────────────────────
  #
  # Distance decides the delivery fee, and MAP_AND_ROUTING requires a fare to
  # be explainable afterwards. A shop nudging its own pin would move every
  # future fare with nothing on the order saying why.
  it "cannot move its own map pin" do
    was_lat = merchant.latitude

    patch "/api/v1/merchant/profile",
          params: { merchant: { latitude: 34.9, longitude: 69.9 } }, headers: auth, as: :json

    expect(merchant.reload.latitude).to eq(was_lat),
                                        "a shop moved its own pin, which silently re-prices every future delivery"
  end

  it "cannot change its own commission rate or name" do
    was_rate = merchant.commission_rate
    was_name = merchant.name

    patch "/api/v1/merchant/profile",
          params: { merchant: { commission_rate: 0, name: "Free Food" } }, headers: auth, as: :json

    expect(merchant.reload.commission_rate).to eq(was_rate), "a shop set its own commission to zero"
    expect(merchant.name).to eq(was_name)
  end

  # Door 5: an audit row for every intervention, before AND after. "Prep time
  # is 40" answers nothing without "it was 15".
  it "records what changed, from what, and by whom" do
    expect {
      patch "/api/v1/merchant/profile",
            params: { merchant: { prep_time_minutes: 40 } }, headers: auth, as: :json
    }.to change { AuditLog.where(action: "merchant.profile_updated").count }.by(1)

    log = AuditLog.where(action: "merchant.profile_updated").last
    expect(log.actor).to eq(owner)
    expect(log.before.to_s).to include("15"), "the previous value is missing, so the row cannot be read"
    expect(log.after.to_s).to include("40")
  end

  it "is refused to somebody else's owner" do
    other = create(:user, :merchant_owner)
    create(:merchant, owner: other)
    other_auth = { "Authorization" => "Bearer #{UserSession.issue!(other).last}" }

    patch "/api/v1/merchant/profile",
          params: { merchant: { prep_time_minutes: 99 } }, headers: other_auth, as: :json

    expect(merchant.reload.prep_time_minutes).to eq(15)
  end
end
