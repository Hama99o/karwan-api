require "rails_helper"

# ═══ A WIRED POLICY THAT CANNOT REFUSE IS A DEAD FILE WITH EXTRA STEPS ═════
#
# The caller sweep on 2026-09-18 found `CourierWalletPolicy#top_up?/adjust?/
# settle?` and `CourierProfilePolicy#approve?/reject?` had no caller anywhere.
# Nothing was exploitable — `Admin::ApplicationController` gates on
# `authenticate_admin_user!` and every one of those methods is `= admin?`, so
# the session gate enforced the identical rule. That coincidence is the whole
# danger: a file that reads as the authorization for crediting a courier's
# wallet was not what enforced it, so anyone changing that rule would have
# edited a file that changes nothing.
#
# CLAUDE.md records the same lesson from edu-safi: five endpoints where the
# correct scope existed, was correct, and was never consulted. "Write the scope
# AND use it."
#
# ── WHY THIS SPEC EXISTS AND NOT JUST THE `authorize` LINE ───────────────
#
# Adding `authorize` proves nothing on its own. Every policy method here
# returns `admin?`, every console session is an admin, so the wired and unwired
# versions are indistinguishable from the outside — a green suite looks the
# same either way. **The only proof that a policy is consulted is making it
# REFUSE and watching the action not happen.**
#
# So each example forces one policy method false and asserts the intervention
# did not occur. If the `authorize` line were removed, every example here goes
# red; that is the point of it.
RSpec.describe "the admin policies are consulted", type: :request do
  let(:admin) do
    AdminUser.create!(name: "Najibullah", email: "ops@karwan.af", password: "a-long-test-password")
  end

  before do
    post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
  end

  let(:courier) { create(:user, :courier) }
  let(:wallet) { courier.courier_wallet }

  def refuse!(policy, method)
    allow_any_instance_of(policy).to receive(method).and_return(false)
  end

  describe "CourierWalletPolicy" do
    before { wallet.update!(balance: 100, credit_line: 500) }

    it "is consulted for a top-up: refusing it moves no money" do
      expect {
        post "/admin/courier_wallets/#{wallet.id}/top_up", params: { amount: "500", note: "deposit" }
      }.to change { wallet.reload.balance }.by(500)

      refuse!(CourierWalletPolicy, :top_up?)

      expect {
        post "/admin/courier_wallets/#{wallet.id}/top_up", params: { amount: "500", note: "deposit" }
      }.not_to change { wallet.reload.balance }
    end

    # The most sensitive of the three: free-form, either direction, and the only
    # one whose amount a human invents.
    it "is consulted for an adjustment: refusing it moves no money and writes no audit row" do
      refuse!(CourierWalletPolicy, :adjust?)

      expect {
        post "/admin/courier_wallets/#{wallet.id}/adjust", params: { amount: "-50", note: "correcting a miscount" }
      }.not_to change { wallet.reload.balance }

      expect {
        post "/admin/courier_wallets/#{wallet.id}/adjust", params: { amount: "-50", note: "correcting a miscount" }
      }.not_to change(AuditLog, :count)
    end

    it "is consulted for a settlement" do
      refuse!(CourierWalletPolicy, :settle?)

      expect {
        post "/admin/courier_wallets/#{wallet.id}/settle",
             params: { counted_amount: "50", counted_by_name: "Najibullah" }
      }.not_to change(Settlement, :count)
    end
  end

  describe "CourierProfilePolicy" do
    let(:applicant) { create(:courier_profile, :documented) }

    it "is consulted for an approval: refusing it leaves the courier unapproved" do
      refuse!(CourierProfilePolicy, :approve?)

      patch "/admin/courier_profiles/#{applicant.id}/approve"

      expect(applicant.reload).not_to be_verification_approved
    end

    it "is consulted for a rejection" do
      refuse!(CourierProfilePolicy, :reject?)

      patch "/admin/courier_profiles/#{applicant.id}/reject", params: { reason: "documents unreadable" }

      expect(applicant.reload).not_to be_verification_rejected
    end
  end

  # ── AND THE POLICY MUST STILL SAY YES TO A REAL ADMIN ────────────────────
  #
  # The failure mode of this whole change, and the one that would take the
  # console out for everybody: `ApplicationPolicy#admin?` reads
  # `user&.role?(:admin)`, and `AdminUser` has no `role?` at all. Pointing
  # Pundit at the console's actor without teaching the policy what that actor is
  # would refuse every admin — silently, as a redirect.
  describe "the console's own actor" do
    it "counts an AdminUser as an admin" do
      expect(CourierWalletPolicy.new(admin, wallet).adjust?).to be true
    end

    it "still refuses somebody who is not an admin at all" do
      expect(CourierWalletPolicy.new(create(:user, :customer), wallet).adjust?).to be false
      expect(CourierWalletPolicy.new(nil, wallet).adjust?).to be false
    end
  end
end
