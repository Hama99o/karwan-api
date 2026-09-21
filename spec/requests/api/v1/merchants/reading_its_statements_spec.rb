require "rails_helper"

# R19: a shop's own earnings view — "sales, commission deducted, net received".
RSpec.describe "A merchant reads its own statements", type: :request do
  def json = JSON.parse(response.body)

  let(:owner) { create(:user, :merchant_owner) }
  let(:merchant) { create(:merchant, owner: owner) }
  let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(owner).last}" } }

  def statement_for(m, start_on: 7.days.ago.to_date, items: 1_200, commission: 150)
    m.statements.create!(period_start: start_on, period_end: start_on + 6, currency: "AFN",
                         orders_count: 3, items_total: items, commission: commission,
                         net_received: items - commission, issued_at: Time.current)
  end

  it "returns the three figures a shop asks about" do
    statement_for(merchant)

    get "/api/v1/merchant/statements", headers: auth

    expect(response).to have_http_status(:ok)
    row = json["statements"].first
    expect(row["items_total"].to_f).to eq(1_200)
    expect(row["commission"].to_f).to eq(150)
    expect(row["net_received"].to_f).to eq(1_050)
    expect(row["reconciles"]).to be(true)
  end

  # `items_total` is what their food sold for. The customer total includes a
  # delivery fee that was never the shop's, and sending it here would overstate
  # their sales by the whole delivery line.
  it "reports the food total and not the customer total" do
    statement_for(merchant, items: 1_200)

    get "/api/v1/merchant/statements", headers: auth

    expect(json["statements"].first.keys).not_to include("customer_total"),
                                                 "the shop is being shown money that was never theirs"
  end

  it "never shows another shop's statements" do
    mine = statement_for(merchant)
    other = create(:merchant, owner: create(:user, :merchant_owner))
    theirs = statement_for(other, items: 9_999)

    get "/api/v1/merchant/statements", headers: auth

    ids = json["statements"].map { |s| s["id"] }
    expect(ids).to include(mine.id), "its own statement is missing, so the exclusion below is vacuous"
    expect(ids).not_to include(theirs.id)
  end

  it "shows the newest period first" do
    old = statement_for(merchant, start_on: 21.days.ago.to_date)
    recent = statement_for(merchant, start_on: 7.days.ago.to_date)

    get "/api/v1/merchant/statements", headers: auth

    expect(json["statements"].map { |s| s["id"] }).to eq([ recent.id, old.id ])
  end

  # Issuing is on a schedule so every shop's week is cut at the same boundary,
  # and re-issuing would defeat the snapshot.
  it "offers the shop no way to issue or change one" do
    actions = Rails.application.routes.routes.filter_map { |route|
      next unless route.defaults[:controller] == "api/v1/merchants/statements"

      route.defaults[:action]
    }.uniq

    expect(actions).to eq(%w[index])
  end
end
