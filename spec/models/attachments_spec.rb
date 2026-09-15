require "rails_helper"

# These exist because of a real bug: seven `has_one_attached` declarations were
# in place and `active_storage:install` had never been run. There were no
# attachment tables at all.
#
# Nothing caught it. `ruby -c` passed, rubocop passed, `zeitwerk:check` passed —
# the macro does not touch the database at class-definition time — and 103 specs
# passed because not one of them attached a file. It would have surfaced on the
# first photo upload, in the feature that matters most in this market.
#
# So: every declared attachment is exercised here. A macro that needs a table is
# not verified by a suite that never uses it.
RSpec.describe "Active Storage attachments", type: :model do
  # A plain IO hash rather than Rack::Test::UploadedFile: this is an --api app,
  # so rack-test's helpers are not loaded in a model spec and the class resolves
  # to something with a different signature.
  def png
    { io: Rails.root.join("spec/fixtures/files/photo.png").open,
      filename: "photo.png", content_type: "image/png" }
  end

  def audio
    { io: Rails.root.join("spec/fixtures/files/voice_note.m4a").open,
      filename: "voice_note.m4a", content_type: "audio/mp4" }
  end

  it "has the Active Storage tables, which is what was actually missing" do
    expect(ActiveRecord::Base.connection.table_exists?("active_storage_blobs")).to be true
    expect(ActiveRecord::Base.connection.table_exists?("active_storage_attachments")).to be true
  end

  describe "CatalogItem#photo" do
    # The single most important visual element in the app: a large share of
    # Afghan adults cannot read fluently, so the photo of the actual food IS the
    # menu item. An item without one is close to unorderable.
    it "attaches and reports attached" do
      item = create(:catalog_item)
      item.photo.attach(png)

      expect(item.photo).to be_attached
      expect(item.reload.photo.blob.content_type).to eq("image/png")
    end
  end

  describe "Merchant attachments" do
    it "attaches a logo, a storefront photo and a licence photo independently" do
      merchant = create(:merchant)
      merchant.logo.attach(png)
      merchant.storefront_photo.attach(png)
      merchant.license_photo.attach(png)

      expect(merchant.reload.logo).to be_attached
      expect(merchant.storefront_photo).to be_attached
      expect(merchant.license_photo).to be_attached
    end
  end

  describe "CourierProfile attachments" do
    # A courier carries our cash and goods we have paid for, so they have to be
    # identifiable. These are the tazkira and a face.
    it "attaches an ID document, a selfie and a vehicle photo" do
      profile = create(:courier_profile)
      profile.id_document.attach(png)
      profile.selfie.attach(png)
      profile.vehicle_photo.attach(png)

      expect(profile.reload.id_document).to be_attached
      expect(profile.selfie).to be_attached
      expect(profile.vehicle_photo).to be_attached
    end
  end

  describe "Address#voice_note" do
    # The highest-value feature in the app for this market. Typing "the blue
    # gate near the mosque, second floor" in Pashto is the hardest action in the
    # whole flow; saying it is trivial.
    let(:address) { create(:address) }

    it "attaches audio and flips the queryable flag" do
      expect(address.has_voice_note).to be false

      address.voice_note.attach(audio)
      address.save!

      expect(address.reload.has_voice_note).to be true
      expect(address.voice_note).to be_attached
      expect(Address.with_voice_note).to include(address)
    end

    # The flag exists so a courier screen can say "there is a voice note"
    # without loading the blob. If it can disagree with reality it is worse than
    # not having it.
    it "cannot claim a voice note it does not have" do
      address.update!(has_voice_note: true)

      expect(address.reload.has_voice_note).to be false
    end

    it "clears the duration when the audio goes away" do
      address.voice_note.attach(audio)
      address.update!(voice_note_seconds: 12)
      expect(address.reload.voice_note_seconds).to eq(12)

      address.voice_note.purge
      address.save!

      expect(address.reload.voice_note_seconds).to be_nil
      expect(address.has_voice_note).to be false
    end

    it "rejects a note longer than a courier will listen to at a junction" do
      address.voice_note.attach(audio)
      address.voice_note_seconds = Address::MAX_VOICE_NOTE_SECONDS + 1

      expect(address).not_to be_valid
    end
  end

  describe "Address#navigable?" do
    # A pin alone is often not enough in a city navigated by landmark, so an
    # address needs the pin plus at least one human description — spoken or
    # written. The voice note is what makes that reachable for someone who
    # cannot type Pashto.
    it "is true with a pin and a spoken landmark, with no text at all" do
      address = create(:address, landmark_note: nil)
      address.voice_note.attach(audio)
      address.save!

      expect(address.reload).to be_navigable
    end

    it "is true with a pin and a written landmark" do
      expect(create(:address)).to be_navigable
    end

    it "is false with a bare pin and no description of any kind" do
      expect(create(:address, landmark_note: nil)).not_to be_navigable
    end
  end
end
