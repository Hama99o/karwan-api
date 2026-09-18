require "rails_helper"

# ═══ NO IMAGE GOES TO A PHONE AT CAMERA RESOLUTION ═════════════════════════
#
# Measured 2026-09-18 (docs/NOTES.md). A merchant card carries TWO images, the
# default page is 20, and `MAX_IMAGE_BYTES` is 5 MB — so one Home screen could
# pull ~200 MB of originals to render a logo at about 96 px. With variants the
# same screen is ~1 MB. That is the screen the app opens with, over a metered
# connection, paid for by users Hamma9900 recruited one conversation at a time.
#
# ── WHY THIS GATE ASSERTS SHAPE AND NOT BYTES ────────────────────────────
#
# The obvious gate — attach a photo, measure the response — is the one that
# cannot work here, and the reason is worth keeping. **Every measurement of
# this problem taken before today was measuring the fixtures**: the seeded
# photos are generated 2-7 KB cards, so a byte assertion passes just as happily
# with variants as without, and reports ~0.2 MB for a screen that will cost
# 120 MB in production. A gate whose verdict depends on the size of a test
# fixture is measuring the fixture.
#
# So this asserts the two things that are true regardless of what any fixture
# weighs: a served image DECLARES a variant, and the URL we hand out IS the
# variant. Those hold for a 2 KB fixture and a 5 MB photograph alike.
RSpec.describe "images served to a client are resized" do
  # ── The domain, derived from the serializers rather than listed here ──────
  #
  # Every `Attachments::PublicUrl.for(x.attachment, ...)` call in app/serializers,
  # which is by definition every attachment this API hands to a client.
  CALL_SITES = Dir.glob(Rails.root.join("app/serializers/**/*.rb")).flat_map { |file|
    File.readlines(file).each_with_index.filter_map do |line, i|
      match = line.match(/Attachments::PublicUrl\.for\(\s*[\w.]*?\.(\w+)([^)]*)\)/)
      next unless match

      { file: file.sub("#{Rails.root}/", ""), line: i + 1,
        attachment: match[1],
        # The variant NAME, not merely whether one was passed. Asserting only
        # that `variant:` appears would pass a typo, and a typo is silent here.
        variant: match[2][/variant:\s*:(\w+)/, 1]&.to_sym }
    end
  }.freeze

  # Attachments deliberately served whole, each with the reason. Anything NOT
  # here must declare and use a variant, so adding an image field to a
  # serializer turns this red until somebody decides which it is.
  SERVED_WHOLE = {
    "voice_note" => "audio — a landmark note recorded by the customer, nothing to resize"
  }.freeze

  it "found the call sites, or every example below is asserting nothing" do
    expect(CALL_SITES.size).to be >= 4
  end

  it "hands out a variant for every image, and says why for anything it does not" do
    whole = CALL_SITES.reject { |site| site[:variant] }
    unexplained = whole.reject { |site| SERVED_WHOLE.key?(site[:attachment]) }

    expect(unexplained).to be_empty,
                           "these serializers hand a client the ORIGINAL blob: " \
                           "#{unexplained.map { |s| "#{s[:file]}:#{s[:line]} (#{s[:attachment]})" }.join(', ')}. " \
                           "Declare a variant on the model and pass `variant:`, or add it to SERVED_WHOLE with a reason."
  end

  # The other half: passing `variant: :thumb` for a variant nobody declared
  # falls back to the original, silently and by design — `PublicUrl` fails open
  # so a missing thumbnail never means a missing photo. That safety is exactly
  # what would hide a typo, so the declaration is asserted separately.
  # WRITTEN WEAKER FIRST, and a plant caught it: it checked that the model
  # declared SOME named variant, so `variant: :thumbnail` against a model
  # declaring `:thumb` passed — the exact typo the example is named for. The
  # title claimed more than the body asserted, which is the whole catalogue of
  # lying instruments in one line.
  it "declares on the model every variant the serializers ask for, BY NAME" do
    Rails.application.eager_load!

    missing = CALL_SITES.select { |site| site[:variant] }.reject do |site|
      ActiveRecord::Base.descendants.any? do |model|
        model.try(:attachment_reflections)&.dig(site[:attachment])&.named_variants&.key?(site[:variant])
      end
    end

    expect(missing).to be_empty,
                       "asked for a variant that no model declares (PublicUrl fails open, so this is " \
                       "SILENT): #{missing.map { |s| "#{s[:file]}:#{s[:line]} (#{s[:attachment]})" }.join(', ')}"
  end

  # ── AND THE URL ACTUALLY HANDED OUT, over HTTP ───────────────────────────
  #
  # The structural half above can be right while the response is wrong. Active
  # Storage serves originals from `/blobs/` and variants from
  # `/representations/`, so the route in the URL is the proof, and it does not
  # care what the fixture weighs.
  describe "the browse screen the app opens with", type: :request do
    let!(:merchant) { create(:merchant, is_open: true) }

    before do
      merchant.logo.attach(io: Rails.root.join("spec/fixtures/files/photo.png").open,
                           filename: "logo.png", content_type: "image/png")
    end

    it "sends the resized logo, not the original blob" do
      get "/api/v1/public/merchants"

      url = JSON.parse(response.body).fetch("merchants").first["logo_url"]
      expect(url).to be_present
      expect(url).to include("/representations/"),
                     "the Home screen is serving original blobs — this is the 120 MB case"
      expect(url).not_to match(%r{/blobs/redirect/})
    end
  end
end
