require "rails_helper"

# ═══ A REASSIGNMENT AFTER THE SHOP IS PAID IS NOT A REASSIGNMENT ═══════════
#
# `MONEY_AND_SETTLEMENT.md` §8: *"After pickup, reassignment is not a
# reassignment — it is a new order plus a loss... the code must treat the two
# cases separately... branch on `merchant_paid_at`."*
#
# The console's reassign branched on nothing. Reproduced over HTTP before this
# file existed — courier A pays the shop 350, the operator reassigns to B, B
# finishes:
#
#   B's steps: go_to_merchant(done), pay_merchant(done), go_to_customer*, …
#   A's job now: nil
#   commission charged to: Courier B       A wallet 5000.0  B wallet 4950.0
#
# B is TOLD HE PAID THE SHOP, which he never did, and is sent to the customer
# with no food. A's job vanishes from his phone while he holds the food, and
# nothing ties his 350 to him any more. B pays A's commission.
#
# What SHOULD happen after pickup — a new order, whose wallet bears the first
# advance — is §8's open question and Hamma9900's. So this refuses the swap and
# says why, which decides nothing; before pickup it is unchanged, because then
# *"nothing moved"* and reassigning is exactly right.
RSpec.describe "no reassignment after the shop is paid", type: :request do
  let(:admin) { AdminUser.create!(name: "Ops", email: "ops@karwan.af", password: "a-long-test-password") }
  let(:merchant) { create(:merchant) }
  let(:first) { create(:user, :courier, name: "Courier A") }
  let(:second) { create(:user, :courier, name: "Courier B") }

  before do
    post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
  end

  def reassign(order)
    patch "/admin/orders/#{order.id}/reassign", params: { courier_id: second.id }
  end

  context "once the first courier has paid the shop" do
    let(:order) { create(:order, :picked_up, merchant: merchant, courier: first, merchant_paid_at: 5.minutes.ago) }

    it "leaves the job with the courier who holds the food, and writes no reassignment" do
      reassign(order)

      expect(order.reload.courier_id).to eq(first.id)
      expect(AuditLog.where(action: "order.reassigned", target: order)).to be_empty
    end

    it "tells the operator why, and what the case actually is" do
      reassign(order)
      follow_redirect!

      expect(CGI.unescapeHTML(response.body)).to include("Courier A has already paid the shop")
    end
  end

  # The discriminating case is `merchant_paid_at`, not the status: §8's fork is
  # "had the first courier already paid the restaurant?" A `ready` order whose
  # courier has paid (the pay step and the pickup are one tap today, but the
  # column is the fact the document names) must be refused too — and a
  # `ready` one that has not been paid must still move.
  it "decides on whether the shop was paid, not on the status name" do
    paid = create(:order, :ready, merchant: merchant, courier: first, merchant_paid_at: 1.minute.ago)
    unpaid = create(:order, :ready, merchant: merchant, courier: first)

    reassign(paid)
    reassign(unpaid)

    expect([ paid.reload.courier_id, unpaid.reload.courier_id ]).to eq([ first.id, second.id ])
  end
end
