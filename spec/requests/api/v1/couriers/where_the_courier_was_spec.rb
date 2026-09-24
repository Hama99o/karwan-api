require "rails_helper"

# ═══ "THE FOOD NEVER ARRIVED" — AND WHERE HE WAS WHEN HE SAID IT DID ═══════
#
# `REALTIME_AND_SCALE.md` §4 and `REQUIREMENTS.md` R15: *"Position at the
# moments that get disputed. Where the courier was when they marked picked up
# and delivered... it is the only evidence when a customer says the food never
# arrived. Recommended; not built."*
#
# `courier_profiles` keeps one position, overwritten seconds later by design,
# so the position AT the moment exists only if it is copied at the moment.
#
# ── THE DISCRIMINATING INPUTS ARE IN THIS FILE ON PURPOSE ─────────────────
#
# 1. The courier MOVES between pickup and delivery. A build that read the
#    profile at display time, or copied the latest fix onto every row, would
#    show the same point twice; this file asserts two different points.
# 2. A STALE fix is recorded with its age, not dropped — so "no fix at all" and
#    "an old fix" are not the same nil.
# 3. An operator and a timeout move the same job while the courier HAS a fix,
#    and neither row carries it — his position on a move he did not make would
#    read as though he had.
RSpec.describe "where the courier was when they moved the job", type: :request do
  let(:courier) { create(:user, :courier) }
  let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(courier).last}" } }
  let(:merchant) { create(:merchant, latitude: 34.5553, longitude: 69.2075) }

  let(:at_the_counter) { [ 34.555300, 69.207500 ] }
  let(:at_the_door)    { [ 34.531200, 69.166100 ] }

  before do
    courier.courier_profile.update!(is_available: true, accepted_job_kinds: %w[delivery ride])
    courier.courier_wallet.update!(balance: 5_000, credit_line: 500)
    stand_at(*at_the_counter)
  end

  def stand_at(lat, lng, fixed_at: Time.current)
    courier.courier_profile.update!(last_latitude: lat, last_longitude: lng, location_updated_at: fixed_at)
  end

  def delivery(status: :ready)
    create(:order, :with_items, status, merchant: merchant, courier: courier,
                                        items_total: 400, delivery_fee: 100, customer_total: 500,
                                        commission: 50, courier_fee: 100, merchant_payout: 350)
  end

  # Through the real endpoint rather than a factory state: a job built straight
  # into `picked_up` has no pickup transition, so its first step never reads as
  # done and the next advance is refused.
  def picked_up_order
    delivery.tap do |order|
      post "/api/v1/courier/jobs/delivery/#{order.id}/advance", params: { step_key: "pay_merchant" }, headers: auth
      expect(response).to have_http_status(:ok)
    end
  end

  def row(job, to_status)
    job.reload.transitions.find_by!(to_status: to_status)
  end

  def point(transition)
    [ transition.courier_latitude&.to_f, transition.courier_longitude&.to_f ]
  end

  it "records the counter at pickup and the door at delivery, two different points" do
    order = delivery

    post "/api/v1/courier/jobs/delivery/#{order.id}/advance", params: { step_key: "pay_merchant" }, headers: auth
    expect(response).to have_http_status(:ok)

    travel 20.minutes
    stand_at(*at_the_door)
    post "/api/v1/courier/jobs/delivery/#{order.id}/advance",
         params: { step_key: "collect_and_deliver" }, headers: auth
    expect(response).to have_http_status(:ok)

    expect(point(row(order, "picked_up"))).to eq(at_the_counter)
    expect(point(row(order, "delivered"))).to eq(at_the_door)
  end

  # The most disputed moment of all — "nobody was home" — is a failure, not a
  # delivery, and a per-job pair of pickup/delivery columns would have missed it.
  it "records the door when the courier reports the customer did not answer" do
    order = picked_up_order
    stand_at(*at_the_door)

    post "/api/v1/courier/jobs/delivery/#{order.id}/problem",
         params: { reason: "nobody_home" }, headers: auth
    expect(response).to have_http_status(:ok)

    expect(point(row(order, "failed"))).to eq(at_the_door)
  end

  it "keeps a stale fix with its age, so it cannot pass for one taken at the door" do
    order = picked_up_order
    fixed = 7.minutes.ago.change(usec: 0)
    stand_at(*at_the_door, fixed_at: fixed)

    post "/api/v1/courier/jobs/delivery/#{order.id}/advance",
         params: { step_key: "collect_and_deliver" }, headers: auth
    expect(response).to have_http_status(:ok)

    delivered = row(order, "delivered")
    expect(point(delivered)).to eq(at_the_door)
    expect(delivered.courier_located_at).to eq(fixed)
    expect(delivered.courier_position).to match(/\A34\.531200, 69\.166100 — fix 4[0-9]{2}s before\z/)
  end

  it "records nothing, rather than a made-up point, for a courier who never sent a fix" do
    order = delivery
    courier.courier_profile.update!(last_latitude: nil, last_longitude: nil, location_updated_at: nil)

    post "/api/v1/courier/jobs/delivery/#{order.id}/advance", headers: auth
    expect(response).to have_http_status(:ok)

    picked_up = row(order, "picked_up")
    expect(point(picked_up)).to eq([ nil, nil ])
    expect(picked_up.courier_located_at).to be_nil
    expect(picked_up.courier_position).to be_nil
  end

  it "does not put the courier's position on a move he did not make as the courier" do
    operator_failed = delivery(status: :picked_up)
    timed_out = delivery(status: :picked_up)
    admin = AdminUser.create!(name: "Najibullah", email: "ops@karwan.af", password: "a-long-test-password")

    expect(operator_failed.transition_to!(:failed, actor: nil, admin_user: admin, actor_role: :admin)).to be(true)
    expect(timed_out.transition_to!(:failed, actor: nil, actor_role: :admin)).to be(true)

    [ operator_failed, timed_out ].each do |order|
      expect(point(row(order, "failed"))).to eq([ nil, nil ])
    end
    # The guard's real input: a courier is also a customer (one identity,
    # correction 18), and cancelling his own lunch is not a claim made at a
    # place. Operator and timeout moves have no actor at all, so without this
    # example the role check could be deleted and every line here stay green.
    lunch = create(:order, :with_items, :placed, merchant: merchant, customer: courier)
    expect(lunch.transition_to!(:cancelled, actor: courier, actor_role: :customer)).to be(true)
    expect(point(row(lunch, "cancelled"))).to eq([ nil, nil ])

    # And the courier's own move on the same setup DOES carry it, so the nils
    # above are the actor rule rather than a fixture with no fix in it.
    mine = delivery
    expect(mine.transition_to!(:picked_up, actor: courier, actor_role: :courier)).to be(true)
    expect(point(row(mine, "picked_up"))).to eq(at_the_counter)
  end

  # Same method, both demand types: a passenger saying "he never came" is the
  # ride's version of the same dispute.
  it "records the pickup point when a driver announces arrival for a ride" do
    trip = create(:trip, :accepted, courier: courier)

    expect(trip.transition_to!(:arrived, actor: courier, actor_role: :courier)).to be(true)

    expect(point(row(trip, "arrived"))).to eq(at_the_counter)
  end

  it "shows the operator the point and its age on the order's page" do
    order = picked_up_order
    stand_at(*at_the_door, fixed_at: 40.seconds.ago)
    post "/api/v1/courier/jobs/delivery/#{order.id}/advance",
         params: { step_key: "collect_and_deliver" }, headers: auth
    expect(response).to have_http_status(:ok)

    admin = AdminUser.create!(name: "Najibullah", email: "ops@karwan.af", password: "a-long-test-password")
    post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
    get "/admin/orders/#{order.id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("34.531200, 69.166100 — fix 40s before")
  end
end
