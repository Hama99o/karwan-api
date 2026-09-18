require "rails_helper"

# ═══ A PROFILE PHOTO, AND A WAY TO TAKE IT DOWN ════════════════════════════
#
# Hamma9900: "we should have user edit profile photo etc also man."
#
# Two things are deliberate and both are his requirement rather than taste:
#
# 1. **Removing is as easy as setting.** People change their mind about a
#    photograph of their own face, and a user who cannot take it down has to
#    ring support — which on this platform is a human with a phone, in Dari, in
#    Kabul. So removal is its own verb on its own route.
#
# 2. **It ships with its variant.** docs/NOTES.md records the measurement:
#    eight attachments across five models, no variants anywhere, originals
#    served at whatever the camera produced. One Home screen could pull ~200 MB
#    to render images at about 96 px. The avatar does not join that problem.
RSpec.describe "Api::V1::Me avatar", type: :request do
  def json
    JSON.parse(response.body)
  end

  let(:user) { create(:user, :customer) }
  let(:auth) { { "Authorization" => "Bearer #{UserSession.issue!(user).last}" } }

  def photo(name: "photo.png", type: "image/png")
    Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/#{name}"), type)
  end

  describe "setting it" do
    it "attaches the photo and returns a URL for it" do
      patch "/api/v1/me", params: { avatar: photo }, headers: auth

      expect(response).to have_http_status(:ok)
      expect(user.reload.avatar).to be_attached
      expect(json.dig("user", "avatar_url")).to be_present
    end

    # THE VARIANT, not the original. A URL that points at the full-size blob is
    # the defect this shipped to avoid, and the two are only distinguishable by
    # the route they use — `representations` is the resized one.
    # Stubbed because whether a variant can be MADE depends on the machine —
    # libvips is in the production image and on no dev box here. Reading the
    # real answer would make this assert "variant" in CI and "original" locally,
    # which reports the environment rather than the code. Both branches are
    # driven in `spec/serializers/served_images_are_resized_spec.rb`.
    it "returns the resized variant rather than the original blob" do
      allow(Attachments::PublicUrl).to receive(:variants_processable?).and_return(true)

      patch "/api/v1/me", params: { avatar: photo }, headers: auth

      expect(json.dig("user", "avatar_url")).to include("/representations/"),
                                                "this is the original blob URL — the variant is not being served"
    end

    it "is absolute, because a native <Image> has no origin to resolve against" do
      patch "/api/v1/me", params: { avatar: photo }, headers: auth

      expect(json.dig("user", "avatar_url")).to match(%r{\Ahttps?://})
    end

    it "is nil for somebody who has not set one" do
      get "/api/v1/me", headers: auth

      expect(json.dig("user", "avatar_url")).to be_nil
    end

    it "leaves the other profile fields alone" do
      user.update!(name: "Najibullah")

      patch "/api/v1/me", params: { avatar: photo }, headers: auth

      expect(user.reload.name).to eq("Najibullah")
    end
  end

  # `has_one_attached` validates NOTHING on its own — not the type, not the
  # size. merchant.rb:43 says so plainly, which is why `validates_attached` is
  # declared rather than the macro trusted.
  describe "what it refuses" do
    # WRITTEN THE OTHER WAY ROUND FIRST, and the failure was the test's.
    # Handing it a real PNG labelled `image/heic` was accepted — because Active
    # Storage IDENTIFIES the bytes and corrects the content type, so it stored a
    # PNG and the validation quite rightly allowed it. The client's label is not
    # evidence, which is the behaviour we want and is worth asserting.
    it "believes the bytes, not the client's label" do
      mislabelled = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/photo.png"), "image/heic")

      patch "/api/v1/me", params: { avatar: mislabelled }, headers: auth

      expect(response).to have_http_status(:ok)
      expect(user.reload.avatar.content_type).to eq("image/png")
    end

    it "refuses a file that is genuinely not an image" do
      not_an_image = Tempfile.new([ "notes", ".txt" ])
      not_an_image.write("this is not a photograph of anybody")
      not_an_image.rewind

      patch "/api/v1/me",
            params: { avatar: Rack::Test::UploadedFile.new(not_an_image.path, "text/plain") },
            headers: auth

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.avatar).not_to be_attached
    ensure
      not_an_image&.close!
    end

    it "refuses a file over the 5 MB cap, which is a cost decision" do
      oversized = Tempfile.new([ "big", ".png" ], binmode: true)
      oversized.write("\x89PNG\r\n\x1a\n" + ("0" * (AttachableDocuments::MAX_IMAGE_BYTES + 1)))
      oversized.rewind

      patch "/api/v1/me",
            params: { avatar: Rack::Test::UploadedFile.new(oversized.path, "image/png") },
            headers: auth

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.avatar).not_to be_attached
    ensure
      oversized&.close!
    end
  end

  describe "removing it" do
    before { patch "/api/v1/me", params: { avatar: photo }, headers: auth }

    it "takes the photo down and says so in the same payload shape" do
      expect(user.reload.avatar).to be_attached

      delete "/api/v1/me/avatar", headers: auth

      expect(response).to have_http_status(:ok)
      expect(json.dig("user", "avatar_url")).to be_nil
      expect(user.reload.avatar).not_to be_attached
    end

    # A client retrying after a dropped connection must not be told it failed
    # for having succeeded — this is the connection the whole product is
    # designed around.
    it "is idempotent: removing one that is not there is still a 200" do
      delete "/api/v1/me/avatar", headers: auth
      delete "/api/v1/me/avatar", headers: auth

      expect(response).to have_http_status(:ok)
      expect(user.reload.avatar).not_to be_attached
    end

    it "removes nobody else's" do
      other = create(:user, :customer)
      patch "/api/v1/me", params: { avatar: photo },
            headers: { "Authorization" => "Bearer #{UserSession.issue!(other).last}" }
      expect(other.reload.avatar).to be_attached

      delete "/api/v1/me/avatar", headers: auth

      expect(other.reload.avatar).to be_attached
      expect(user.reload.avatar).not_to be_attached
    end
  end
end
