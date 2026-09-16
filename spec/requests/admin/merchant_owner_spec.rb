require "rails_helper"

# THE PATH HAMMA9900 WILL ACTUALLY USE, on the day he signs his first
# restaurant: the console's generic merchant form, with the owner set to the
# phone number of the person sitting across the table.
#
# Specced at this layer rather than only on the model because that is where it
# lands — `docs/NOTES.md` records the general form of that mistake, and this
# very endpoint had five pages returning 500 with 1,078 model examples green.
RSpec.describe "Setting a merchant's owner in the console", type: :request do
  let(:admin) { AdminUser.create!(name: "Najibullah", email: "ops@karwan.af", password: "a-long-test-password") }
  let(:merchant) { create(:merchant, owner: nil) }
  let(:restaurateur) { create(:user, phone: "+93700000555", name: "حاجی نعیم") }

  before do
    post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
  end

  it "grants the merchant role, so the owner can reach the merchant tab" do
    patch "/admin/merchants/#{merchant.id}", params: { merchant: { owner_id: restaurateur.id } }

    expect(merchant.reload.owner).to eq(restaurateur)
    expect(restaurateur.reload.role?(:merchant_owner)).to be true
  end

  # The whole point of the role: the merchant endpoints are role-gated, and
  # `OrderPolicy::MerchantScope` returns nothing without it. Asserted through
  # the API the phone actually calls, because "the role row exists" and "the
  # board loads" are different claims.
  it "lets them load their own order board straight away" do
    patch "/admin/merchants/#{merchant.id}", params: { merchant: { owner_id: restaurateur.id } }

    session, token = UserSession.issue!(restaurateur.reload, requested_role: "merchant_owner")
    get "/api/v1/merchant/orders", headers: { "Authorization" => "Bearer #{token}" }

    expect(session.active_role).to eq("merchant_owner")
    expect(response).to have_http_status(:ok)
  end

  it "revokes the role when the restaurant is taken back" do
    patch "/admin/merchants/#{merchant.id}", params: { merchant: { owner_id: restaurateur.id } }
    patch "/admin/merchants/#{merchant.id}", params: { merchant: { owner_id: "" } }

    expect(merchant.reload.owner).to be_nil
    expect(restaurateur.reload.role?(:merchant_owner)).to be false
  end

  it "refuses the whole thing to a signed-out visitor" do
    delete "/admin/logout"

    patch "/admin/merchants/#{merchant.id}", params: { merchant: { owner_id: restaurateur.id } }

    expect(merchant.reload.owner).to be_nil
    expect(restaurateur.reload.role?(:merchant_owner)).to be false
  end
end
