require "rails_helper"

# A REVIEW THAT ASKS, from the console.
#
# Before this the operator's only options were approve or reject, so an
# applicant who had merely forgotten a photo had to be REFUSED in order to be
# told anything. An applicant told he was refused is a courier we convinced and
# then lost, and on the supply side that is the expensive direction.
RSpec.describe "Reviewing a courier application", type: :request do
  let(:admin) { AdminUser.create!(name: "Najibullah", email: "ops@karwan.af", password: "a-long-test-password") }
  let(:applicant) { create(:user, :customer) }
  let!(:profile) { create(:courier_profile, user: applicant, full_name: "عبدالله رحیمی") }

  before do
    post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
  end

  describe "asking for more" do
    it "moves it to its own state, which is not a refusal" do
      patch "/admin/courier_profiles/#{profile.id}/ask_for_more",
            params: { note: "تذکره خوانا نیست" }

      expect(profile.reload.verification_status).to eq("needs_more")
      expect(profile.review_note).to eq("تذکره خوانا نیست")
    end

    # ── THE STALE REASON, AND WHY THIS FIXTURE IS SHAPED LIKE THIS ───────────
    #
    # A refusal REVERSED into a request is the only way a stale
    # `rejection_reason` can exist, so it is the only fixture in which clearing
    # it can be observed. My first version asserted `rejection_reason` was nil
    # on a profile that had never been rejected — nil either way, so deleting
    # the clearing line broke nothing.
    #
    # `docs/TESTING.md`: make the sources disagree. And the case is real, not
    # contrived: a reviewer who refused somebody and then thinks better of it
    # is exactly who uses this action, and an applicant shown "we cannot accept
    # you" beside "send us your tazkira" would not know which one counts.
    it "clears a refusal reason it is reversing" do
      profile.reject!(by: nil, reason: "ضمانت‌کننده انکار کرد")

      patch "/admin/courier_profiles/#{profile.id}/ask_for_more", params: { note: "دوباره بفرست" }

      expect(profile.reload.verification_status).to eq("needs_more")
      expect(profile.rejection_reason).to be_nil
      expect(profile.review_note).to eq("دوباره بفرست")
    end

    it "records WHO asked, on the row, not only in a log" do
      patch "/admin/courier_profiles/#{profile.id}/ask_for_more"

      expect(profile.reload.verified_by_admin_user).to eq(admin)
      expect(profile.reviewed_at).to be_present
    end

    it "works without a note, because `missing` already lists absent fields" do
      patch "/admin/courier_profiles/#{profile.id}/ask_for_more"

      expect(profile.reload.verification_status).to eq("needs_more")
      expect(profile.review_note).to be_nil
    end

    it "tells the applicant" do
      expect { patch "/admin/courier_profiles/#{profile.id}/ask_for_more" }
        .to have_enqueued_job(Notifications::CourierReviewAlertJob).with(profile.id)
    end

    it "logs the intervention with what is still wanted" do
      patch "/admin/courier_profiles/#{profile.id}/ask_for_more", params: { note: "blurry" }

      log = AuditLog.for_action("courier.more_asked").newest_first.first
      expect(log.admin_user).to eq(admin)
      expect(log.details["note"]).to eq("blurry")
      expect(log.details["missing"]).to be_present
    end

    # They were never on shift, so nothing to take them off — and flipping
    # `is_available` here would give one flag two meanings.
    it "does not touch their availability" do
      profile.update!(is_available: false)

      patch "/admin/courier_profiles/#{profile.id}/ask_for_more"

      expect(profile.reload.is_available).to be false
    end

    it "refuses a signed-out visitor, changing nothing" do
      delete "/admin/logout"

      patch "/admin/courier_profiles/#{profile.id}/ask_for_more"

      expect(profile.reload.verification_status).to eq("pending")
    end
  end

  describe "the applicant's own view of it" do
    it "shows the note and the state, as their own screen reads them" do
      patch "/admin/courier_profiles/#{profile.id}/ask_for_more", params: { note: "تذکره خوانا نیست" }

      token = UserSession.issue!(applicant).last
      get "/api/v1/courier/registration", headers: { "Authorization" => "Bearer #{token}" }

      body = JSON.parse(response.body).fetch("registration")
      expect(body["verification_status"]).to eq("needs_more")
      expect(body["review_note"]).to eq("تذکره خوانا نیست")
      # NOT a rejection, and the app renders the two differently.
      expect(body["rejection_reason"]).to be_nil
      expect(body["missing"]).to be_present
      expect(body["can_start"]).to be false
    end
  end

  describe "a genuine refusal still works, and still tells them" do
    it "needs a reason" do
      patch "/admin/courier_profiles/#{profile.id}/reject"

      expect(profile.reload.verification_status).to eq("pending")
    end

    it "records the reason and notifies" do
      expect {
        patch "/admin/courier_profiles/#{profile.id}/reject", params: { reason: "ضمانت‌کننده انکار کرد" }
      }.to have_enqueued_job(Notifications::CourierReviewAlertJob)

      expect(profile.reload.verification_status).to eq("rejected")
      expect(profile.rejection_reason).to eq("ضمانت‌کننده انکار کرد")
    end
  end
end
