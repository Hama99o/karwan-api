require "rails_helper"

# A CUSTOMER IS TOLD WHEN THEIR ORDER DIES (karwan-42 via Hamma9901,
# 25 Sept 2026).
#
# Their only push was the arrival one. A shop that never answered, a
# cancellation, a failure at the gate: learned only by opening the app. Now
# every ending they did NOT cause pushes, with the reason as a code so the
# app can say the next step. Their own cancellation does not: they just did it.
RSpec.describe "When an order dies, the customer is told", type: :request do
  include ActiveJob::TestHelper

  let(:customer) { create(:user, :customer) }
  let(:owner) { create(:user, :merchant_owner) }
  let(:merchant) { create(:merchant, owner: owner) }
  let(:order) { create(:order, :with_items, customer: customer, merchant: merchant) }
  let(:sent) { [] }
  let(:client) { instance_double(Notifications::FcmClient) }

  before do
    create(:device_token, user: customer, token: "customers-phone")
    allow(client).to receive(:send_to) do |tokens, **options|
      sent << { tokens: tokens }.merge(options)
      Notifications::FcmClient::Result.new(delivered: tokens.size, failed: 0, status: :ok)
    end
    allow(Notifications::FcmClient).to receive(:new).and_return(client)
  end

  # The push runs THE MOMENT it is enqueued (inside the request), so a caller
  # that wrote the reason after the transition would push without it, and
  # these examples would go red. The reason is written IN the transition.
  def as_it_happens(&) = perform_enqueued_jobs(only: Notifications::CustomerOrderEndedJob, &)
  def deliver_the_pushes = nil

  it "tells them when the shop rejects it, with the reason" do
    as_it_happens do
      post "/api/v1/merchant/orders/#{order.id}/reject", params: { reason: "out_of_stock" },
                                                         headers: { "Authorization" => "Bearer #{UserSession.issue!(owner).last}" }
    end
    deliver_the_pushes

    expect(sent.sole).to include(tokens: [ "customers-phone" ], title_key: "customer.order_rejected.title")
    expect(sent.sole[:data]).to include(ended: "rejected", reason: "out_of_stock", code: order.code)
  end

  # The urgent one: two minutes after placing, the shop simply never answered.
  it "tells them when the shop never answered" do
    order # placed now, then left unanswered
    travel 3.minutes
    as_it_happens { Dispatch::JobTimeoutsJob.perform_now }

    expect(sent.sole[:data]).to include(ended: "rejected", reason: "no_answer")
  end

  it "tells them when an operator cancels it" do
    admin = AdminUser.create!(name: "Najibullah", email: "ops@karwan.af", password: "a-long-test-password")
    post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
    as_it_happens { patch "/admin/orders/#{order.id}/cancel" }

    expect(sent.sole).to include(title_key: "customer.order_cancelled.title")
    expect(sent.sole[:data]).to include(ended: "cancelled", reason: "other")
  end

  it "tells them when it failed at the gate" do
    order.update!(status: :picked_up, picked_up_at: Time.current)
    token = UserSession.issue!(courier = create(:user, :courier)).last
    order.update!(courier: courier)
    as_it_happens do
      post "/api/v1/courier/jobs/delivery/#{order.id}/problem", params: { reason: "nobody_home" }, headers: { "Authorization" => "Bearer #{token}" }
    end

    expect(sent.sole[:data]).to include(ended: "failed", reason: "nobody_home")
  end

  it "does not tell them about a cancellation they made themselves" do
    post "/api/v1/customer/orders/#{order.id}/cancel", headers: { "Authorization" => "Bearer #{UserSession.issue!(customer).last}" }
    deliver_the_pushes

    expect(order.reload).to be_cancelled
    expect(sent).to be_empty
  end

  it "says nothing on a delivery, which has its own push" do
    order.update!(status: :picked_up, picked_up_at: Time.current)
    order.transition_to!(:delivered, actor: nil, actor_role: :admin)
    deliver_the_pushes

    expect(sent).to be_empty
  end

  # The whole point of `transition_to!(..., with:)`: no moment exists at which
  # the order has ended but its reason is missing.
  it "never shows an ended order without its reason" do
    order.transition_to!(:rejected, actor: nil, actor_role: :admin, with: { rejection_reason: :too_busy })

    expect(Notifications::CustomerOrderEndedJob).to have_been_enqueued.with(order.id)
    expect(Order.find(order.id).rejection_reason).to eq("too_busy")
  end
end
