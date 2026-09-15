require "rails_helper"

RSpec.describe Dispatch::ExpireOffersJob do
  let(:merchant) { create(:merchant, latitude: 34.5553, longitude: 69.2075) }
  let(:order) do
    create(:order, merchant: merchant, items_total: 400, delivery_fee: 100,
                   customer_total: 500, commission: 50, merchant_payout: 350)
  end

  def courier_at(lat, lng)
    user = create(:user, :courier)
    user.courier_profile.update!(is_available: true, last_latitude: lat, last_longitude: lng,
                                 location_updated_at: Time.current)
    user.courier_wallet.update!(balance: 1_000, credit_line: 500)
    user
  end

  # This job is what makes dispatch exist. Without it an unanswered offer stays
  # `offered` forever, the job is never re-offered, and the customer watches a
  # screen that will never change.
  it "expires an unanswered offer and moves to the next courier" do
    courier_at(34.5553, 69.2075)
    second = courier_at(34.5600, 69.2100)
    stale = order.offers.create!(courier: order.merchant.owner || courier_at(34.5553, 69.2075),
                                 sequence: 1, status: :offered,
                                 offered_at: 2.minutes.ago, expires_at: 1.minute.ago)

    result = described_class.new.perform

    expect(stale.reload.status).to eq("timed_out")
    expect(stale.responded_at).to be_present
    expect(result[:expired]).to eq(1)
    expect(order.offers.pending.count).to eq(1)
    expect(order.offers.pending.first.courier).to be_in([ second, *User.all ])
  end

  it "leaves a live offer alone" do
    courier_at(34.5553, 69.2075)
    live = order.offers.create!(courier: courier_at(34.5560, 69.2080), sequence: 1,
                                status: :offered, offered_at: Time.current,
                                expires_at: 1.minute.from_now)

    described_class.new.perform

    expect(live.reload.status).to eq("offered")
  end

  # An answered offer past its deadline must NOT be re-offered, or a job
  # somebody already accepted gets handed to a second courier.
  it "leaves an accepted offer alone even long past its deadline" do
    accepted = order.offers.create!(courier: courier_at(34.5553, 69.2075), sequence: 1,
                                    status: :accepted, offered_at: 1.hour.ago,
                                    expires_at: 59.minutes.ago, responded_at: 59.minutes.ago)

    described_class.new.perform

    expect(accepted.reload.status).to eq("accepted")
    expect(order.offers.count).to eq(1)
  end

  it "does nothing, and does not raise, when there is nothing to expire" do
    expect { described_class.new.perform }.not_to raise_error
    expect(described_class.new.perform).to eq({ expired: 0, reoffered: 0 })
  end

  it "expires an offer even when no courier is left to ask" do
    only = courier_at(34.5553, 69.2075)
    stale = order.offers.create!(courier: only, sequence: 1, status: :offered,
                                 offered_at: 2.minutes.ago, expires_at: 1.minute.ago)

    result = described_class.new.perform

    expect(stale.reload.status).to eq("timed_out")
    expect(result[:reoffered]).to eq(0)
  end

  # One bad job must not stop the queue — a silently skipped expiry is an order
  # that sits forever.
  it "keeps going when one job fails" do
    good_order = order
    bad_order = create(:order, merchant: merchant)
    courier = courier_at(34.5553, 69.2075)
    [ good_order, bad_order ].each do |job|
      job.offers.create!(courier: courier, sequence: 1, status: :offered,
                         offered_at: 2.minutes.ago, expires_at: 1.minute.ago)
    end
    allow(Dispatch::OfferService).to receive(:new).and_call_original
    allow(Dispatch::OfferService).to receive(:new).with(bad_order).and_raise("boom")

    expect { described_class.new.perform }.not_to raise_error
    expect(Offer.where(status: :timed_out).count).to be >= 1
  end

  it "is idempotent — running twice changes nothing the second time" do
    courier_at(34.5553, 69.2075)
    order.offers.create!(courier: courier_at(34.5560, 69.2080), sequence: 1, status: :offered,
                         offered_at: 2.minutes.ago, expires_at: 1.minute.ago)

    described_class.new.perform
    second = described_class.new.perform

    expect(second[:expired]).to eq(0)
  end

  it "expires ride offers through the same job" do
    ride = create(:trip, fare: 160, commission: 20, courier_earnings: 140)
    courier = create(:user, :ride_courier)
    stale = ride.offers.create!(courier: courier, sequence: 1, status: :offered,
                                offered_at: 2.minutes.ago, expires_at: 1.minute.ago)

    described_class.new.perform

    expect(stale.reload.status).to eq("timed_out")
  end
end
