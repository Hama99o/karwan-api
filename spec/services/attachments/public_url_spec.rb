require "rails_helper"

# A PHOTO URL A PHONE CAN ACTUALLY FETCH.
#
# Every serializer returned `only_path: true` — `/rails/active_storage/...` —
# and a browser resolves that against its origin. **A native
# `<Image source={{ uri }}>` has no origin.** So the first real photograph
# would have rendered as an empty box, identical to the empty box that exists
# when there is no photo at all: the symptom is the state it replaces, which is
# the worst possible way for a bug to hide.
#
# It had never been exercised because no seed attached a photo. The seeds land
# in the same commit as this fix, which is the only reason it was found before
# Hamma9900 found it on his screen.
RSpec.describe Attachments::PublicUrl do
  let(:merchant) { create(:merchant) }

  def attach!
    merchant.storefront_photo.attach(
      io: Rails.root.join("spec/fixtures/files/photo.png").open,
      filename: "photo.png", content_type: "image/png"
    )
    merchant.storefront_photo
  end

  around do |example|
    original = ENV["APP_BASE_URL"]
    example.run
    ENV["APP_BASE_URL"] = original
  end

  it "is absolute, so a native image view can fetch it" do
    ENV["APP_BASE_URL"] = "https://api.karwan.af"

    url = described_class.for(attach!)

    expect(url).to start_with("https://api.karwan.af/")
    expect(url).to include("/rails/active_storage/")
  end

  # THE ASSERTION THAT CATCHES THE BUG, stated as the rule rather than as a
  # prefix: any scheme-less URL is unusable on a device, whatever it looks like.
  it "never returns a host-relative path" do
    ENV["APP_BASE_URL"] = "https://api.karwan.af"

    expect(described_class.for(attach!)).to match(%r{\Ahttps?://})
  end

  it "does not double the slash when the base carries one" do
    ENV["APP_BASE_URL"] = "https://api.karwan.af/"

    # by-design: the subject is a non-empty URL string, not a collection.
    expect(described_class.for(attach!)).not_to include("af//rails")
  end

  # Nil rather than a URL to nothing, which every caller already handles — and
  # which is the same lie as a boolean claiming a file exists.
  it "is nil when nothing is attached" do
    expect(described_class.for(merchant.logo)).to be_nil
    expect(described_class.for(nil)).to be_nil
  end

  describe "where the host comes from" do
    it "prefers an explicit base url" do
      ENV["APP_BASE_URL"] = "https://photos.karwan.af"

      expect(described_class.base_url).to eq("https://photos.karwan.af")
    end

    it "falls back to the deploy host, over https" do
      ENV["APP_BASE_URL"] = nil
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("KAMAL_HOST").and_return("karwan.example.com")

      expect(described_class.base_url).to eq("https://karwan.example.com")
    end

    # 3017, not Rails' 3000 — another app on this box holds 3000, and that cost
    # a morning once.
    it "falls back to localhost on the port this app actually serves" do
      ENV["APP_BASE_URL"] = nil

      expect(described_class.base_url).to eq("http://localhost:3017")
    end

    # A deployed API serving `http://localhost` photo URLs would look correct
    # in every log and show nothing on every phone, so `bin/preflight` asks.
    it "reports whether the address is configured or merely inferred" do
      ENV["APP_BASE_URL"] = "https://api.karwan.af"
      expect(described_class).to be_configured

      ENV["APP_BASE_URL"] = nil
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("KAMAL_HOST").and_return(nil)
      expect(described_class).not_to be_configured
    end
  end

  # ── AND THROUGH THE SERIALIZERS, which is where it lands ──────────────────
  #
  # A helper that returns the right thing and four serializers that do not call
  # it is the shape of bug docs/NOTES.md records twice over.
  describe "every serializer that returns a file" do
    before { ENV["APP_BASE_URL"] = "https://api.karwan.af" }

    it "gives the merchant's photos absolute urls" do
      attach!
      merchant.logo.attach(io: Rails.root.join("spec/fixtures/files/photo.png").open,
                           filename: "logo.png", content_type: "image/png")

      rendered = Customers::MerchantSerializer.render_as_hash(merchant.reload, view: :detailed,
                                                                              options: { locale: "fa", from: nil })

      expect(rendered[:logo_url]).to start_with("https://api.karwan.af/")
      expect(rendered[:storefront_photo_url]).to start_with("https://api.karwan.af/")
    end

    it "gives a catalog item's photo an absolute url" do
      item = create(:catalog_item, merchant: merchant)
      item.photo.attach(io: Rails.root.join("spec/fixtures/files/photo.png").open,
                        filename: "dish.png", content_type: "image/png")

      rendered = Customers::CatalogSerializer.render_as_hash(
        [ item.catalog_category.reload ], view: :default
      )

      urls = rendered.flat_map { |c| c[:items].map { |i| i[:photo_url] } }.compact
      expect(urls).not_to be_empty
      expect(urls).to all(start_with("https://api.karwan.af/"))
    end

    # The voice note is the same contract: a courier's app has to PLAY it, and
    # a relative path plays nothing.
    it "gives an address's voice note an absolute url" do
      address = create(:address)
      address.voice_note.attach(io: Rails.root.join("spec/fixtures/files/voice_note.m4a").open,
                                filename: "note.m4a", content_type: "audio/mp4")

      rendered = Customers::AddressSerializer.render_as_hash(address.reload)

      expect(rendered[:voice_note_url]).to start_with("https://api.karwan.af/")
    end
  end
end

# ── THE GATE THAT COULD NEVER OPEN ─────────────────────────────────────────
#
# `variants_processable?` read `require "vips" && true`. Ruby binds `&&` tighter
# than a parenthesis-less argument, so that is `require("vips" && true)` —
# `require(true)` — which raises `TypeError` straight into the method's own
# `rescue ... false`. The mini_magick branch had the same shape. **Neither
# branch could return true on any machine**, however well libvips was
# installed.
#
# It hid for two reasons, and the second is the one worth remembering:
#
#   1. The method had no spec of its own. This block is that spec.
#   2. FIVE call-site specs stub it to `true`
#      (`served_images_are_resized_spec`, `avatar_spec`,
#      `onboarding_a_restaurant_spec`, `first_restaurant_rehearsal_spec`).
#      Every place that needed the "variants work" path had to force it, and a
#      stub that is always needed is evidence about the real method that nobody
#      read as evidence.
#
# WHAT IT COST: `bin/preflight` turns a false here into a FAILING step on a
# deployed box and tells the reader to install libvips — which is already in
# both Dockerfile stages. A blocking red whose remedy was already applied.
RSpec.describe Attachments::PublicUrl, ".variants_processable?" do
  # THE ASSERTION THAT RUNS EVERYWHERE, and the one that would have caught it.
  #
  # The behavioural example below cannot catch this bug on a box with no
  # libvips — which is this box, and therefore CI — because there the correct
  # answer and the broken answer are both `false`. A source assertion has no
  # such blind spot: the defect is in the expression, so the expression is what
  # is asserted. Keep both; they fail in different places.
  it "never decides a require succeeded by using its value in a boolean" do
    source = Rails.root.join("app/services/attachments/public_url.rb").read
    body = source[/def variants_processable\?.*?\n      end/m]

    # STRIP COMMENTS BEFORE MATCHING. The first version of this example failed
    # against the FIXED file, because the comment inside the method quotes the
    # broken expression in order to explain it. A grep-based gate is a tiny
    # parser, and one that cannot tell a comment from a statement reports the
    # documentation as the defect. docs/TESTING.md says this in its own words;
    # this example was written without reading it and reproduced the mistake
    # within the hour.
    body = body.to_s.lines.reject { |line| line =~ /\A\s*#/ }.join

    expect(body).not_to match(/require\s+["'][^"']+["']\s*&&/),
      "`require \"x\" && y` parses as `require(\"x\" && y)`, which raises " \
      "TypeError and is swallowed by the rescue — the gate can then never open"

    # `require` returns FALSE for an already-loaded feature, so even
    # `(require "vips") && true` would answer differently depending on whether
    # something else touched vips first. The only honest test is whether the
    # require RAISES.
    expect(body).not_to match(/=\s*require\s/)
  end

  # Asserts the answer matches reality on whatever box this runs on. On a
  # machine with libvips it must be true; on one without, false. It is a real
  # assertion in both directions — it is simply blind to the bug above on a box
  # where the library is absent.
  it "agrees with whether the configured processor can actually be loaded" do
    processor = Rails.application.config.active_storage.variant_processor
    skip "only :vips and :mini_magick are handled" unless %i[vips mini_magick].include?(processor)

    library = processor == :vips ? "vips" : "mini_magick"
    loadable =
      begin
        require library
        true
      rescue LoadError
        false
      end

    described_class.remove_instance_variable(:@variants_processable) if
      described_class.instance_variable_defined?(:@variants_processable)

    expect(described_class.variants_processable?).to eq(loadable)
  end
end
