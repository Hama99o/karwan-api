require "rails_helper"

# ═══ CLOSING YOUR OWN ACCOUNT ══════════════════════════════════════════════
#
# Apple and Google both refuse an app that offers account creation without
# in-app deletion, so this exists for compliance rather than because anybody
# asked for it. It is still the most dangerous endpoint in the API: the person
# pressing it may be holding our cash.
#
# ── THE REFUSALS ARE THE FEATURE ─────────────────────────────────────────
#
# A courier who has collected customer cash and not settled it must NOT be able
# to close the account — that is money walking out through a door it never
# comes back through. Same for a wallet with a balance in EITHER direction: a
# negative balance is money they owe us, and a positive one is prepaid credit we
# owe THEM, which makes closing over it worse than the first case, not better.
#
# And each refusal names itself, because it is fixable. A courier told only "no"
# concludes the app is broken; one told "settle up first" goes and settles up.
RSpec.describe "Api::V1::Me account deletion", type: :request do
  def json
    JSON.parse(response.body)
  end

  let(:user) { create(:user, :customer) }
  let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(user).last}" } }

  describe "a customer with nothing outstanding" do
    it "closes the account and says so in a body the app can render" do
      delete "/api/v1/me", headers: auth

      expect(response).to have_http_status(:ok)
      expect(json["deleted"]).to be true
      expect(user.reload).to be_discarded
    end

    # One-way door 6. The row survives because the books need it, and every
    # order carries its own `customer_phone` snapshot anyway.
    it "discards rather than destroying, so order history survives" do
      order = create(:order, :delivered, customer: user)

      delete "/api/v1/me", headers: auth

      expect(User.unscoped.find_by(id: user.id)).to be_present
      expect(order.reload.customer_phone).to be_present
    end

    # The phone in their hand must stop working, not continue on a token that
    # outlives the account.
    it "revokes every session, so the app is signed out" do
      other_device = UserSession.issue!(user).last

      delete "/api/v1/me", headers: auth

      get "/api/v1/me", headers: { "Authorization" => "Bearer #{other_device}" }
      expect(response).to have_http_status(:unauthorized)
    end

    # One-way door 5: an audit row for every intervention, and closing your own
    # account is one you made yourself. Without it, an operator restoring the
    # account from the console cannot tell a mistaken tap from a support call.
    it "writes an audit row naming the person who did it" do
      expect { delete "/api/v1/me", headers: auth }.to change(AuditLog, :count).by(1)

      log = AuditLog.newest_first.first
      expect(log.action).to eq("user.account_closed")
      expect(log.actor_id).to eq(user.id)
    end
  end

  describe "a courier the platform still has money with" do
    let(:user) { create(:user, :courier) }
    let(:wallet) { user.courier_wallet }

    before { wallet.update!(balance: 0, credit_line: 500) }

    it "refuses while they are holding our cash, and says to settle" do
      create(:order, :delivered, courier: user, commission: 50)
      expect(Couriers::CashPosition.new(user).held).to be_positive,
                                                      "holding nothing — the refusal below would prove nothing"

      delete "/api/v1/me", headers: auth

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("holding_cash")
      expect(json["error"]).to match(/settle/i)
      expect(user.reload).not_to be_discarded
    end

    it "refuses while they OWE us, from a negative balance" do
      wallet.update!(balance: -200)

      delete "/api/v1/me", headers: auth

      expect(json["code"]).to eq("wallet_unsettled")
      expect(user.reload).not_to be_discarded
    end

    # The case that is easy to miss, and it is the one where WE are the ones
    # taking something: prepaid credit belongs to the courier.
    it "refuses while WE owe THEM, from a positive balance" do
      wallet.update!(balance: 350)

      delete "/api/v1/me", headers: auth

      expect(json["code"]).to eq("wallet_unsettled")
      expect(user.reload).not_to be_discarded
    end

    it "refuses while a job is in progress" do
      create(:order, :picked_up, courier: user)

      delete "/api/v1/me", headers: auth

      expect(json["code"]).to eq("live_job")
      expect(user.reload).not_to be_discarded
    end

    # THE PAIRED POSITIVE. Every refusal above is worthless unless the same
    # courier, once square with us, can actually close the account.
    it "allows it once the wallet is square and the work is done" do
      order = create(:order, :delivered, courier: user, commission: 50)
      expect(Couriers::CashPosition.new(user).held).to be_positive,
                                                      "nothing was held, so the settling below proves nothing"

      # Settling is what moves the job from `collected` to `settled`, which is
      # what `CashPosition#held` counts — not a wallet entry.
      order.update!(payment_status: :settled)

      delete "/api/v1/me", headers: auth

      expect(response).to have_http_status(:ok), "a settled courier cannot close their account: #{json['error']}"
      expect(user.reload).to be_discarded
    end
  end

  describe "a customer mid-delivery" do
    it "refuses while an order is on its way" do
      create(:order, :picked_up, customer: user)

      delete "/api/v1/me", headers: auth

      expect(json["code"]).to eq("live_order")
      expect(user.reload).not_to be_discarded
    end
  end

  describe "a shop owner with orders in the kitchen" do
    let(:user) { create(:user, :merchant_owner) }

    it "refuses while the shop has orders in flight" do
      merchant = create(:merchant, owner: user)
      create(:order, :ready, merchant: merchant)

      delete "/api/v1/me", headers: auth

      expect(json["code"]).to eq("merchant_orders_in_flight")
      expect(user.reload).not_to be_discarded
    end
  end
end
