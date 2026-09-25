require "rails_helper"

# The board polls every 10 s per open shop. When nothing has changed it now
# answers 304 before its queries run. Its key carries the minute, because the
# card's "waiting N min" and overdue flag come from the clock (decided: up to
# 59 s late is acceptable; the minutes are floored to whole minutes anyway).
RSpec.describe "the merchant board answers 304 when nothing changed", type: :request do
  let(:owner) { create(:user, :merchant_owner) }
  let(:merchant) { create(:merchant, owner: owner) }
  let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(owner).last}" } }
  let!(:order) { create(:order, :with_items, merchant: merchant) }

  around { |example| travel_to(Time.zone.parse("2026-09-24 20:00:10")) { example.run } }

  # THE SHAPE THE APP SENDS (karwan-mobile's board asks `page[size]=100`).
  # This spec first polled with no page at all, a request the app never
  # makes, and e93db6e's raw `params[:page]` in the key was a 500 for every
  # real poll while all five examples here were green.
  APP_PAGE = { page: { number: 1, size: 100 } }.freeze

  def poll(etag = nil, params: APP_PAGE)
    get "/api/v1/merchant/orders", params: params, headers: etag ? auth.merge("If-None-Match" => etag) : auth
    response
  end

  def queries_during
    n = 0
    counter = ->(*, payload) { n += 1 unless payload[:name] == "SCHEMA" || payload[:sql] =~ /\A\s*(BEGIN|COMMIT|SAVEPOINT|RELEASE)/ }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    n
  end

  it "answers the same poll 304, with no body" do
    etag = poll.headers["ETag"]
    expect(etag).to be_present

    expect(poll(etag)).to have_http_status(:not_modified)
    expect(response.body).to be_empty
  end

  # What a 304 must NOT do is the board's own work: loading the orders, their
  # lines, their options and their transition history.
  it "skips the board's queries when it answers 304" do
    etag = poll.headers["ETag"]
    seen = []
    watch = ->(*, payload) { seen << payload[:sql] }
    ActiveSupport::Notifications.subscribed(watch, "sql.active_record") { poll(etag) }

    expect(response).to have_http_status(:not_modified)
    expect(seen.grep(/FROM "(order_items|order_item_options|status_transitions)"/)).to be_empty
    expect(seen.grep(/SELECT "orders"\.\*/)).to be_empty
  end

  it "answers 200 again the moment an order changes" do
    etag = poll.headers["ETag"]
    travel 5.seconds
    order.acknowledge_by_merchant!(owner)

    expect(poll(etag)).to have_http_status(:ok)
  end

  it "answers 200 again when the minute turns, so 'waiting N min' moves" do
    etag = poll.headers["ETag"]
    travel 55.seconds

    expect(poll(etag)).to have_http_status(:ok)
  end

  it "keys a status filter separately from the live board" do
    live = poll.headers["ETag"]
    poll(params: APP_PAGE.merge(status: "delivered"))

    expect(response.headers["ETag"]).not_to eq(live)
  end

  it "answers the app's real poll, nested page and all, with 200" do
    expect(poll).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to be_present
  end

  it "keys each page separately, and a flat ?page= the same as its nested twin" do
    create(:order, :with_items, merchant: merchant)
    first = poll(params: { page: { number: 1, size: 1 } }).headers["ETag"]
    second = poll(params: { page: { number: 2, size: 1 } }).headers["ETag"]
    flat = poll(params: { page: 1 }).headers["ETag"]
    nested_default = poll(params: { page: { number: 1 } }).headers["ETag"]

    expect(second).not_to eq(first)
    expect(flat).to eq(nested_default)
  end

  # One "load more" too far used to raise Pagy::OverflowError, a 500.
  it "answers a page past the end with an empty page, not an error" do
    poll(params: { page: { number: 9, size: 100 } })

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body.values.find { |v| v.is_a?(Array) }).to eq([])
  end
end
