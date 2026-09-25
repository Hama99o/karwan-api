require "rails_helper"

# A REFUSED FIELD CARRIES A KIND THE APP CAN TRANSLATE.
#
# `field_errors` is `errors.details` flattened, so it carries whatever was
# passed to `errors.add` as the kind. Every custom `errors.add` here passed an
# English sentence, so a courier whose photo was too big got
# `{ selfie: ["must be smaller than 5 MB"] }`, a value the app must never
# quote. The app could only say "check this one". karwan-42 found it by
# capturing real refusals (25 Sept 2026); `readFormRefusal` already maps
# `too_large` and `content_type` to Pashto and Dari.
RSpec.describe "A refusal names its kind", type: :request do
  def json = JSON.parse(response.body)

  let(:user) { create(:user, :customer) }
  let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(user).last}" } }

  def apply(**files)
    post "/api/v1/courier/registration",
         params: { registration: { full_name: "احمد شاه", accepted_job_kinds: %w[delivery] }, **files },
         headers: auth
  end

  it "says a photo is too large" do
    stub_const("AttachableDocuments::MAX_IMAGE_BYTES", 10)
    apply(selfie: fixture_file_upload("photo.png", "image/png"))

    expect(response).to have_http_status(:unprocessable_content)
    expect(json["field_errors"]).to eq("selfie" => [ "too_large" ])
    # The sentence survives for the console and for a developer.
    expect(json["errors"].join).to include("smaller than")
  end

  it "says a file is the wrong kind" do
    apply(selfie: fixture_file_upload("voice_note.m4a", "audio/mp4"))

    expect(json["field_errors"]).to eq("selfie" => [ "content_type" ])
  end

  it "says a job kind is not one of the list, without quoting it" do
    post "/api/v1/courier/registration",
         params: { registration: { full_name: "احمد شاه", accepted_job_kinds: %w[teleport] } }, headers: auth

    expect(json["field_errors"]).to eq("accepted_job_kinds" => [ "inclusion" ])
  end

  # THE GATE. Reads every file in app/ and lib/ whole, so a call split over
  # lines is seen: an `errors.add` whose second argument is a string literal
  # puts prose where a kind belongs.
  it "leaves no errors.add with a sentence for a kind" do
    offenders = Rails.root.glob("{app,lib}/**/*.rb").flat_map do |file|
      File.read(file).scan(/errors\.add\(\s*[^,()]+,\s*["']/).map { "#{file.relative_path_from(Rails.root)}: #{_1}" }
    end

    expect(offenders).to be_empty,
                         "pass a symbol kind and keep the sentence as message:, e.g. " \
                         "errors.add(:photo, :too_large, message: \"…\"):\n#{offenders.join("\n")}"
  end
end
