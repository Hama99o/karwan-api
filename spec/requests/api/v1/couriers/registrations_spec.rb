require "rails_helper"

# THE ONLY WAY A COURIER CAN COME INTO EXISTENCE.
#
# Before this endpoint there was none: no application route, and
# `admin/courier_profiles` offers only index/show/edit/update/approve/reject —
# no `new`, no `create`. So a courier existed only if a seed made one, and the
# admin console was an index over a table nothing could write to.
RSpec.describe "Api::V1::Couriers::Registrations", type: :request do
  def json = JSON.parse(response.body)

  let(:user) { create(:user, :customer) }
  let(:token) { UserSession.issue!(user).last }
  let(:auth) { { "Authorization" => "Bearer #{token}" } }

  let(:tazkira) { fixture_file_upload("photo.png", "image/png") }
  let(:selfie) { fixture_file_upload("photo.png", "image/png") }

  let(:application) do
    {
      registration: {
        full_name: "احمد شاه",
        national_id_number: "1401-1234-56789",
        guarantor_name: "محمد نعیم",
        guarantor_phone: "+93700111222",
        guarantor_relation: "کاکا",
        vehicle_type: "motorbike",
        plate_number: "KBL 4821",
        accepted_job_kinds: %w[delivery ride]
      }
    }
  end

  describe "GET /api/v1/courier/registration" do
    # Not a 404. Most people have never applied, and a failure response would
    # have the app render an error where the right screen is the empty form.
    it "returns null for somebody who has never applied" do
      get "/api/v1/courier/registration", headers: auth

      expect(response).to have_http_status(:ok)
      expect(json["registration"]).to be_nil
    end

    it "refuses without a token" do
      get "/api/v1/courier/registration"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/courier/registration" do
    describe "the happy path" do
      it "creates a pending application with the identity and the guarantor" do
        expect { post "/api/v1/courier/registration", params: application, headers: auth }
          .to change(CourierProfile, :count).by(1)

        expect(response).to have_http_status(:created)
        expect(json.dig("registration", "verification_status")).to eq("pending")
        expect(json.dig("registration", "guarantor_phone")).to eq("+93700111222")
        expect(user.reload.courier_profile.national_id_number).to eq("1401-1234-56789")
      end

      it "accepts the documents" do
        post "/api/v1/courier/registration",
             params: application.merge(id_document: tazkira, selfie: selfie), headers: auth

        expect(response).to have_http_status(:created)
        expect(user.reload.courier_profile.id_document).to be_attached
        expect(json.dig("registration", "documents", "id_document")).to be true
        expect(json.dig("registration", "documents", "vehicle_photo")).to be false
      end

      # Built up over several attempts on purpose: refusing the whole form
      # because one 4 MB tazkira photo timed out is how an application is
      # abandoned on a Kabul connection.
      it "accepts a PARTIAL application and says what is still owed" do
        post "/api/v1/courier/registration",
             params: { registration: { full_name: "احمد شاه" } }, headers: auth

        expect(response).to have_http_status(:created)
        expect(json.dig("registration", "missing"))
          .to include("national_id_number", "guarantor_name", "id_document", "selfie")
        expect(json.dig("registration", "ready_for_approval")).to be false
      end

      it "reports ready once identity, guarantor and both documents are in" do
        post "/api/v1/courier/registration",
             params: application.merge(id_document: tazkira, selfie: selfie), headers: auth

        expect(json.dig("registration", "missing")).to be_empty
        expect(json.dig("registration", "ready_for_approval")).to be true
      end

      # A retry on a bad connection must not be punished, and "you have already
      # applied" is not something to make a courier resolve on their own.
      it "is idempotent — applying twice amends rather than failing" do
        post "/api/v1/courier/registration", params: application, headers: auth
        expect {
          post "/api/v1/courier/registration",
               params: { registration: { work_area: "شهرنو" } }, headers: auth
        }.not_to change(CourierProfile, :count)

        expect(response).to have_http_status(:ok)
        expect(user.reload.courier_profile.work_area).to eq("شهرنو")
        # And the earlier answers survive.
        expect(user.courier_profile.full_name).to eq("احمد شاه")
      end

      it "records that they applied, for the audit trail" do
        expect { post "/api/v1/courier/registration", params: application, headers: auth }
          .to change { AuditLog.where(action: "courier.applied").count }.by(1)
      end
    end

    describe "the refused paths" do
      it "refuses without a token" do
        post "/api/v1/courier/registration", params: application

        expect(response).to have_http_status(:unauthorized)
      end

      # `has_one_attached` validates nothing on its own — not the type, not the
      # size — and this is a VPS with the disk at 90%.
      it "refuses a document that is not an image" do
        post "/api/v1/courier/registration",
             params: application.merge(id_document: fixture_file_upload("voice_note.m4a", "audio/mp4")),
             headers: auth

        expect(response).to have_http_status(:unprocessable_content)
        expect(json["errors"].join).to match(/image/)
      end

      it "refuses an unknown job kind rather than making them silently undispatchable" do
        post "/api/v1/courier/registration",
             params: { registration: application[:registration].merge(accepted_job_kinds: %w[helicopter]) },
             headers: auth

        expect(response).to have_http_status(:unprocessable_content)
        expect(json["errors"].join).to match(/helicopter/)
      end
    end
  end

  describe "PATCH /api/v1/courier/registration" do
    before { post "/api/v1/courier/registration", params: application, headers: auth }

    # A rejected courier must be able to fix what was wrong, or one typo in a
    # guarantor's number ends their application permanently.
    it "lets a REJECTED applicant fix and resubmit, returning them to the queue" do
      user.courier_profile.update!(verification_status: :rejected, rejection_reason: "guarantor unreachable")

      patch "/api/v1/courier/registration",
            params: { registration: { guarantor_phone: "+93700999888" } }, headers: auth

      expect(response).to have_http_status(:ok)
      expect(json.dig("registration", "verification_status")).to eq("pending")
      expect(json.dig("registration", "rejection_reason")).to be_nil
      expect(user.reload.courier_profile.guarantor_phone).to eq("+93700999888")
    end

    # Changing a tazkira number after approval is the shape of fraud this whole
    # flow exists to prevent.
    it "sends an APPROVED courier back to a human if they edit their identity" do
      user.courier_profile.update!(verification_status: :approved, verified_at: Time.current)

      patch "/api/v1/courier/registration",
            params: { registration: { national_id_number: "9999-0000-11111" } }, headers: auth

      expect(user.reload.courier_profile).to be_verification_pending
      expect(AuditLog.where(action: "courier.reopened_application")).to exist
    end

    it "adds a document without wiping the ones already uploaded" do
      patch "/api/v1/courier/registration", params: { id_document: tazkira }, headers: auth
      patch "/api/v1/courier/registration", params: { selfie: selfie }, headers: auth

      profile = user.reload.courier_profile
      expect(profile.id_document).to be_attached
      expect(profile.selfie).to be_attached
    end

    it "never lets one applicant edit another's" do
      other = create(:user, :customer)
      other_token = UserSession.issue!(other).last

      patch "/api/v1/courier/registration",
            params: { registration: { full_name: "someone else" } },
            headers: { "Authorization" => "Bearer #{other_token}" }

      # They have no application of their own, so there is nothing to edit —
      # and crucially they did not edit ours.
      expect(response).to have_http_status(:not_found)
      expect(user.reload.courier_profile.full_name).to eq("احمد شاه")
    end
  end
end
