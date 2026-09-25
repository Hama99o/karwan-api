require "rails_helper"

# THE OFFER HE WAS LOOKING AT IS GONE: SAY WHY, TRUTHFULLY.
#
# karwan-42 found an offer vanished at the next poll with no sentence, and
# the only copy available ("went to another rider") described a race v0
# can't have: one job is offered to one courier at a time. The poll now says
# how his last offer ended, from its own record (Couriers::LastOffer):
# timed_out, taken or withdrawn.
RSpec.describe "Why my offer went", type: :request do
  let(:courier) { create(:user, :courier) }
  let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(courier).last}" } }
  let(:order) { create(:order, :with_items, :ready) }
  let!(:offer) { create(:offer, courier: courier, offerable: order) }
  let(:admin) { AdminUser.create!(name: "Najibullah", email: "ops@karwan.af", password: "a-long-test-password") }

  def poll
    get "/api/v1/courier/offer", headers: auth
    JSON.parse(response.body)
  end

  def as_operator = post("/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } })

  it "while the offer is live, shows the offer and no ending" do
    body = poll

    expect(body["offer"]).to be_present
    expect(body["last_offer"]).to be_nil
  end

  it "says it ran out, even before the sweep has marked it" do
    travel Offer::DEFAULT_TTL + 5.seconds

    expect(poll).to include("offer" => nil, "last_offer" => include("ended" => "timed_out", "job_code" => order.code))
  end

  it "says it ran out once the sweep has marked it" do
    offer.update!(status: :timed_out, responded_at: Time.current)

    expect(poll["last_offer"]).to include("ended" => "timed_out")
  end

  # The one case where "another rider has it" is literally true.
  it "says it was taken when the job is now with another courier" do
    other = create(:user, :courier)
    as_operator
    patch "/admin/orders/#{order.id}/reassign", params: { courier_id: other.id }

    expect(poll["last_offer"]).to include("ended" => "taken")
  end

  it "says it was withdrawn when the job was cancelled under him" do
    order.transition_to!(:cancelled, actor: nil, actor_role: :admin)

    expect(poll).to include("offer" => nil, "last_offer" => include("ended" => "withdrawn"))
  end

  # The bug found building this: a cancelled job stayed on offer.
  it "stops offering a job the moment it ends" do
    order.transition_to!(:cancelled, actor: nil, actor_role: :admin)

    expect(offer.reload).to be_status_superseded
    expect(poll["offer"]).to be_nil
  end

  it "says nothing about an ending older than two minutes" do
    offer.update!(status: :timed_out, responded_at: 3.minutes.ago)

    expect(poll["last_offer"]).to be_nil
  end

  it "says nothing when he answered it himself" do
    offer.update!(status: :declined, responded_at: Time.current)

    expect(poll["last_offer"]).to be_nil
  end
end
