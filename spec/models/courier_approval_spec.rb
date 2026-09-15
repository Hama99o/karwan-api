require "rails_helper"

# APPROVAL IS THREE THINGS, NOT ONE.
#
# It used to set the status and (separately, in the controller) create a wallet,
# and it NEVER granted the `courier` role. The result is the worst kind of bug:
# a courier told they are approved, who then sees no jobs because
# `OrderPolicy::CourierScope` resolves to `none` for a user without the role,
# and cannot even switch into the courier tab because `User#switch_role!`
# refuses a role they do not hold. Every symptom points at the app.
RSpec.describe "approving a courier" do
  let(:admin) { create(:admin_user) }
  let(:user) { create(:user, :customer) }
  let(:profile) do
    create(:courier_profile, user: user, verification_status: :pending,
                             full_name: "احمد شاه", national_id_number: "1401-1",
                             guarantor_name: "نعیم", guarantor_phone: "+93700111222")
  end

  before do
    profile.id_document.attach(io: File.open(file_fixture("photo.png")), filename: "t.png", content_type: "image/png")
    profile.selfie.attach(io: File.open(file_fixture("photo.png")), filename: "s.png", content_type: "image/png")
    user.courier_wallet&.destroy
    user.user_roles.where(role: :courier).destroy_all
    user.reload
  end

  it "grants the status, the ROLE and a WALLET, so the courier can actually work" do
    profile.approve!(by: admin)

    expect(profile.reload).to be_verification_approved
    # The one that was missing. Without it every courier-scoped query is empty.
    expect(user.reload.role?(:courier)).to be true
    expect(user.courier_wallet).to be_present
  end

  it "gives a new courier the credit line, so they can start with nothing" do
    profile.approve!(by: admin)

    expect(user.reload.courier_wallet.credit_line).to eq(Setting.fetch("default_credit_line"))
    expect(user.courier_wallet.balance).to eq(0)
  end

  it "lets them switch into the courier tab, which the missing role prevented" do
    profile.approve!(by: admin)

    expect(user.reload.switch_role!(:courier)).to be_truthy
    expect(user.reload.active_role).to eq("courier")
  end

  it "records WHICH ADMIN approved, on the row" do
    profile.approve!(by: admin)

    # The column pointed at `users` and the console operator is an `AdminUser`,
    # so this could only ever be nil before. CLAUDE.md: "a nil approver on an
    # approved courier is not a valid state."
    expect(profile.reload.verified_by_admin_user).to eq(admin)
  end

  it "refuses an approval with no approver at all" do
    expect { profile.approve!(by: nil) }.to raise_error(ArgumentError, /approver/)
    expect(profile.reload).to be_verification_pending
  end

  it "is idempotent about the role — approving twice does not duplicate it" do
    profile.approve!(by: admin)
    profile.approve!(by: admin)

    expect(user.reload.user_roles.where(role: :courier).count).to eq(1)
  end

  # All three or none. A courier approved with two of the three is a support
  # call nobody can diagnose from the outside.
  it "rolls the status back if the wallet cannot be created" do
    allow(CourierWallet).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(CourierWallet.new))

    expect { profile.approve!(by: admin) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(profile.reload).to be_verification_pending
    expect(user.reload.role?(:courier)).to be false
  end

  describe "#missing_for_approval" do
    it "names what is still owed, as field names the app can translate" do
      bare = create(:courier_profile, user: create(:user, :customer), full_name: nil,
                                      national_id_number: nil, guarantor_name: nil,
                                      guarantor_phone: nil)

      expect(bare.missing_for_approval)
        .to include(:full_name, :national_id_number, :guarantor_name, :guarantor_phone,
                    :id_document, :selfie)
      expect(bare).not_to be_ready_for_approval
    end

    it "is empty once identity, guarantor and both documents are in" do
      expect(profile.missing_for_approval).to be_empty
      expect(profile).to be_ready_for_approval
    end
  end
end
