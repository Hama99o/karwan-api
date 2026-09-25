require "rails_helper"

# A KITCHEN AWAY FROM ITS TABLET (karwan-42's merchant audit, 25 Sept 2026).
#
# The alarm and the board poll are foreground-only, and a placed order the
# shop doesn't answer closes itself as `no_answer` after Order::TIMEOUTS.
# The card showed no clock, and nothing counted the orders lost that way. Now:
# the card says how long is left (from the rule, never a client constant),
# /merchant/today counts today's missed orders, and the board carries the
# last one, so the notice survives the app being backgrounded.
RSpec.describe "A kitchen away from its tablet", type: :request do
  let(:owner) { create(:user, :merchant_owner) }
  let(:merchant) { create(:merchant, owner: owner) }
  let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(owner).last}" } }

  def board
    get "/api/v1/merchant/orders", params: { page: { number: 1, size: 100 } }, headers: auth
    JSON.parse(response.body)
  end

  # Placed long enough ago to be overdue, and closed by the REAL timeout job.
  def missed!
    placed = Time.current - Order::TIMEOUTS.fetch(:placed) - 1.minute
    create(:order, :with_items, merchant: merchant, placed_at: placed, created_at: placed)
    Dispatch::JobTimeoutsJob.perform_now
  end

  def missed_yesterday!
    create(:order, :with_items, merchant: merchant, status: :rejected, rejection_reason: :no_answer,
                                placed_at: 1.day.ago, rejected_at: 1.day.ago + 3.minutes)
  end

  around { |example| travel_to(Time.utc(2026, 9, 25, 8, 0, 0)) { example.run } } # 12:30 in Kabul

  describe "how long is left to answer" do
    it "counts down from the rule the timeout enforces" do
      create(:order, :with_items, merchant: merchant)
      travel 30.seconds

      card = board["orders"].sole
      expect(card["answer_within_seconds"]).to eq(Order::TIMEOUTS.fetch(:placed).to_i - 30)
      expect(Time.zone.parse(card["answer_by"])).to eq(Time.current - 30.seconds + Order::TIMEOUTS.fetch(:placed))
    end

    # A Setting or a code change to the window moves the card with it.
    it "follows the rule if the window changes, rather than a hardcoded two minutes" do
      stub_const("Order::TIMEOUTS", Order::TIMEOUTS.merge(placed: 5.minutes))
      create(:order, :with_items, merchant: merchant)

      expect(board["orders"].sole["answer_within_seconds"]).to eq(300)
    end

    it "is nil once the kitchen has answered" do
      create(:order, :with_items, :accepted, merchant: merchant)

      expect(board["orders"].sole).to include("answer_by" => nil, "answer_within_seconds" => nil)
    end
  end

  describe "orders the kitchen never answered" do
    it "counts today's on /merchant/today" do
      2.times { missed! }
      get "/api/v1/merchant/today", headers: auth

      expect(JSON.parse(response.body)["missed"]).to eq(2)
    end

    it "does not count a missed order from yesterday, in Kabul" do
      missed_yesterday!
      get "/api/v1/merchant/today", headers: auth

      expect(JSON.parse(response.body)["missed"]).to eq(0)
    end

    it "does not count the shop's own refusal as missed" do
      order = create(:order, :with_items, merchant: merchant)
      post "/api/v1/merchant/orders/#{order.id}/reject", params: { reason: "out_of_stock" }, headers: auth
      get "/api/v1/merchant/today", headers: auth

      expect(JSON.parse(response.body)["missed"]).to eq(0)
    end

    it "carries the last one on the board, even with nothing live" do
      missed!
      missed_order = Order.where(rejection_reason: :no_answer).sole

      expect(board).to include("orders" => [], "last_missed" => include("code" => missed_order.code))
    end

    it "carries nothing when none were missed" do
      expect(board["last_missed"]).to be_nil
    end
  end
end
