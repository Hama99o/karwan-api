require "rails_helper"

# F-92: NOTHING EVER ASKED WHAT A COURIER RIDES.
#
# The column defaulted to 0, which is motorbike, and the app never sent it, so
# every courier registered from a phone was a motorbike and dispatch believed
# it. A car driver was refused every car ride and every family ride. The seeds
# and the factory set the column directly, so nothing ever saw the default.
#
# So this drives the app's own path, a registration that does NOT send the
# field, which is what every build before karwan-mobile `d6f313d` did.
RSpec.describe "A courier names his vehicle", type: :request do
  def json = JSON.parse(response.body)

  let(:user) { create(:user, :customer) }
  let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(user).last}" } }
  let(:admin) { AdminUser.create!(name: "Najibullah", email: "ops@karwan.af", password: "a-long-test-password") }

  def apply(**extra)
    post "/api/v1/courier/registration",
         params: {
           registration: {
             full_name: "احمد شاه", national_id_number: "1401-1234-56789",
             guarantor_name: "محمد نعیم", guarantor_phone: "+93700111222",
             accepted_job_kinds: %w[delivery ride], **extra
           },
           id_document: fixture_file_upload("photo.png", "image/png"),
           selfie: fixture_file_upload("photo.png", "image/png")
         },
         headers: auth
  end

  def approve_from_the_console
    post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
    patch "/admin/courier_profiles/#{user.courier_profile.id}/approve"
  end

  describe "an application that does not say" do
    before { apply }

    it "records no vehicle, rather than a motorbike" do
      expect(response).to have_http_status(:created)
      expect(json.dig("registration", "vehicle_type")).to be_nil
      expect(user.reload.courier_profile.vehicle_type).to be_nil
    end

    # A field NAME, never prose: the app renders its own Pashto per field.
    it "tells the applicant the vehicle is still owed" do
      expect(json.dig("registration", "missing")).to eq([ "vehicle_type" ])
      expect(json.dig("registration", "ready_for_approval")).to be false
    end

    it "cannot be approved as an accidental motorbike" do
      approve_from_the_console

      expect(user.reload.courier_profile.verification_status).to eq("pending")
      expect(flash[:alert]).to include("vehicle_type")
    end

    # A console edit of an approved courier can't blank it again either.
    it "is required on an approved profile, not only at the approve button" do
      profile = user.reload.courier_profile
      profile.update!(vehicle_type: :car)
      profile.approve!(by: admin)

      expect(profile.update(vehicle_type: nil)).to be false
      expect(profile.errors.details[:vehicle_type]).to include(error: :blank)
    end
  end

  describe "an application that does" do
    before { apply(vehicle_type: "car") }

    it "is ready, and approves" do
      expect(json.dig("registration", "missing")).to eq([])

      approve_from_the_console

      expect(user.reload.courier_profile).to be_verification_approved
    end

    # The failure the default caused, end to end: a passenger who chose a car.
    it "is offered a car ride as a car" do
      approve_from_the_console
      profile = user.reload.courier_profile
      profile.record_location!(latitude: 34.5401, longitude: 69.1751)
      profile.set_availability!(true)
      trip = create(:trip, vehicle_type: :car, passenger_count: 3)

      reason = Dispatch::Eligibility.new(courier: user, job: trip).reason

      # Nil is eligible. Under the old default this was :wrong_vehicle_class.
      expect(reason).to be_nil
    end
  end
end
