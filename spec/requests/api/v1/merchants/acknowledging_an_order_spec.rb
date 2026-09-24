require "rails_helper"

# ── WAS THE ALERT HEARD, OR ONLY DELIVERED? ────────────────────────────────
#
# PRODUCT.md: the incoming order is "loud and repeating **until acknowledged**",
# on "a cheap tablet propped on a counter in a noisy kitchen", and a merchant
# who never hears it is the most damaging state in the system.
#
# The console could already count a push that reached NO DEVICE. It could not
# see the worse case, because that case looks fine from the server: the push
# arrived, and nobody looked at the screen.
RSpec.describe "A merchant acknowledges an incoming order", type: :request do
  def json = JSON.parse(response.body)

  let(:owner) { create(:user, :merchant_owner) }
  let(:merchant) { create(:merchant, owner: owner) }
  let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(owner).last}" } }
  let!(:order) { create(:order, :with_items, merchant: merchant) }

  it "records when a human first saw it" do
    expect(order.merchant_acknowledged_at).to be_nil, "nothing to prove if it starts acknowledged"

    post "/api/v1/merchant/orders/#{order.id}/acknowledge", headers: auth

    expect(response).to have_http_status(:ok)
    expect(json.dig("order", "acknowledged_at")).to be_present
    expect(order.reload.merchant_acknowledged_by).to eq(owner),
                                                     "in a dispute the question is WHICH person picked the tablet up"
  end

  # ── THE ALARM SCREEN WILL RETRY ─────────────────────────────────────────
  #
  # On a bad connection the tablet cannot know whether its first call landed,
  # so it will send another. If the second overwrote the time, "when did
  # somebody first see this" would always answer "just now" and would always
  # look fine.
  it "keeps the FIRST time when the tablet retries" do
    post "/api/v1/merchant/orders/#{order.id}/acknowledge", headers: auth
    first = order.reload.merchant_acknowledged_at

    travel_to 10.minutes.from_now do
      post "/api/v1/merchant/orders/#{order.id}/acknowledge", headers: auth
    end

    expect(response).to have_http_status(:ok)
    expect(order.reload.merchant_acknowledged_at).to eq(first),
                                                     "a retry moved the time, so the delay is now unmeasurable"
  end

  # Acknowledging says "a human is looking", not "we will cook this". Folding
  # the two together is how a cook under pressure accepts an order they cannot
  # make, just to stop the noise.
  it "does not accept the order or change its state" do
    expect { post "/api/v1/merchant/orders/#{order.id}/acknowledge", headers: auth }
      .not_to change { order.reload.status }

    expect(order.status).to eq("placed")
    expect(order.transitions.count).to eq(0), "acknowledging is not a state transition and must not write one"
  end

  it "is refused to a merchant who does not hold this order" do
    other = create(:user, :merchant_owner)
    create(:merchant, owner: other)
    other_auth = { "Authorization" => "Bearer #{UserSession.issue!(other).last}" }

    post "/api/v1/merchant/orders/#{order.id}/acknowledge", headers: other_auth

    expect(response.status).to be_in([ 403, 404 ])
    expect(order.reload.merchant_acknowledged_at).to be_nil
  end

  describe "what the console sees" do
    # The grace period is the point: an order placed thirty seconds ago is not a
    # problem, it is an order. A tile that counts it is a tile an operator
    # learns to ignore, which is worse than no tile.
    it "is not reported while the order is still fresh" do
      expect(Order.awaiting_acknowledgement.count).to eq(0)
    end

    it "is reported once it has waited and nobody has looked" do
      order.update!(created_at: 5.minutes.ago)

      expect(Order.awaiting_acknowledgement).to include(order)
    end

    it "stops being reported the moment somebody looks" do
      order.update!(created_at: 5.minutes.ago)
      expect(Order.awaiting_acknowledgement).to include(order), "the count must start non-zero or this proves nothing"

      post "/api/v1/merchant/orders/#{order.id}/acknowledge", headers: auth

      expect(Order.awaiting_acknowledgement).not_to include(order)
    end

    # A delivered order that was never acknowledged is history, not a job for
    # an operator tonight.
    it "does not report an order that has moved on" do
      order.update!(created_at: 5.minutes.ago, status: :delivered)

      expect(Order.awaiting_acknowledgement).not_to include(order)
    end
  end

  # ── ACTING ON IT IS SEEING IT ────────────────────────────────────────────
  #
  # The alarm panel offers Accept on the panel itself, so a busy kitchen acts
  # in one tap. That tap must answer "when did a human first see this" too —
  # before, an order accepted without the separate acknowledge call kept
  # `merchant_acknowledged_at` empty forever.
  describe "a board action without the acknowledge call" do
    %w[accept reject].each do |action|
      it "records the acknowledgement when the shop taps #{action.capitalize} straight away" do
        params = action == "reject" ? { reason: "too_busy" } : {}
        post "/api/v1/merchant/orders/#{order.id}/#{action}", params: params, headers: auth

        expect(order.reload.merchant_acknowledged_at).to be_present
        expect(order.merchant_acknowledged_by).to eq(owner)
      end
    end

    it "keeps an earlier acknowledgement's time rather than replacing it with the accept's" do
      post "/api/v1/merchant/orders/#{order.id}/acknowledge", headers: auth
      first = order.reload.merchant_acknowledged_at

      travel 3.minutes do
        post "/api/v1/merchant/orders/#{order.id}/accept", headers: auth
      end

      expect(order.reload.merchant_acknowledged_at).to eq(first)
    end

    it "does not record one when the action is refused" do
      order.update_columns(status: Order.statuses[:cancelled])

      post "/api/v1/merchant/orders/#{order.id}/accept", headers: auth

      expect(order.reload.merchant_acknowledged_at).to be_nil
    end
  end
end
