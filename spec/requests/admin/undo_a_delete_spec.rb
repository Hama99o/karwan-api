require "rails_helper"

# ═══ AN OPERATOR HAS JUST DELETED THE WRONG SHOP ═══════════════════════════
#
# Approved by Hamma9900 after the caller sweep found `SoftDeletable#undiscard!`
# had no caller anywhere — no route, no controller, no dashboard action.
#
# One-way door 6 says soft delete, never hard, so the row was always still
# there. What was missing was any way for a human to bring it back: the undo
# existed in the DATA and required a developer and a Rails console to reach.
# On a console five to ten people work in, that is a phone call to France.
#
# ── THE HALF THAT IS NOT THE CODE ────────────────────────────────────────
#
# His instruction was about the affordance as much as the action: the operator
# who needs this has just made a mistake and is not calm. So the discarded
# record has to be FINDABLE — an undo you cannot navigate to is the same dead
# path it replaces. `deleted_at` is now a list column rather than only a show
# field, because a discarded merchant was already in the list (`scoped_resource`
# is not scoped to `kept`) and looked exactly like a live one.
RSpec.describe "undoing a delete", type: :request do
  let(:admin) do
    AdminUser.create!(name: "Najibullah", email: "ops@karwan.af", password: "a-long-test-password")
  end

  before do
    post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
  end

  describe "a merchant deleted by mistake" do
    let!(:merchant) { create(:merchant, name: "Kabab House") }

    it "is still listed after the delete, and says it is deleted" do
      delete "/admin/merchants/#{merchant.id}"

      get "/admin/merchants"

      expect(response.body).to include("Kabab House"),
                               "a deleted merchant vanishes from the list — there is nothing to click undo ON"
      # The operator must be able to TELL. Before this column the row was
      # indistinguishable from a live shop.
      expect(response.body).to match(/deleted/i)
    end

    it "can be found by the name the operator remembers" do
      delete "/admin/merchants/#{merchant.id}"

      get "/admin/merchants", params: { search: "Kabab House" }

      expect(response.body).to include("Kabab House")
    end

    it "comes back, with its menu, when the operator restores it" do
      item = create(:catalog_item, catalog_category: create(:catalog_category, merchant: merchant))
      delete "/admin/merchants/#{merchant.id}"
      expect(merchant.reload).to be_discarded
      expect(item.reload).to be_discarded, "the menu did not go with it — the restore below proves less"

      patch "/admin/merchants/#{merchant.id}/restore"

      expect(merchant.reload).to be_kept
    end

    # "An operator can undo a delete" and "nobody can tell who did" are two
    # different states, and only one is acceptable on a surface touching money.
    it "records WHO restored it, and that it had been deleted" do
      delete "/admin/merchants/#{merchant.id}"

      expect {
        patch "/admin/merchants/#{merchant.id}/restore"
      }.to change(AuditLog, :count).by(1)

      log = AuditLog.newest_first.first
      expect(log.action).to eq("merchant.restored")
      expect(log.admin_user_id).to eq(admin.id)
      expect(log.before.to_s).to match(/deleted_at/)
    end

    # Two operators on the phone about the same mistake, or one clicking twice.
    it "is idempotent: restoring a live merchant is not an error" do
      patch "/admin/merchants/#{merchant.id}/restore"

      expect(response).to have_http_status(:redirect)
      expect(merchant.reload).to be_kept
    end

    it "restores only the one asked for" do
      other = create(:merchant, name: "Someone Else")
      delete "/admin/merchants/#{merchant.id}"
      delete "/admin/merchants/#{other.id}"

      patch "/admin/merchants/#{merchant.id}/restore"

      expect(merchant.reload).to be_kept
      expect(other.reload).to be_discarded
    end
  end

  # A courier carries a wallet and a ledger, so a deleted one is the most
  # expensive mistake available on this screen.
  describe "a courier deleted by mistake" do
    let!(:courier) { create(:user, :courier, name: "Ahmad") }

    it "comes back, and the restore is audited" do
      courier.discard!

      expect {
        patch "/admin/users/#{courier.id}/restore"
      }.to change(AuditLog, :count).by(1)

      expect(courier.reload).to be_kept
      expect(AuditLog.newest_first.first.action).to eq("user.restored")
    end

    it "is listed while deleted, so it can be found and restored" do
      courier.discard!

      get "/admin/users", params: { search: "Ahmad" }

      expect(response.body).to include("Ahmad")
    end
  end
end
