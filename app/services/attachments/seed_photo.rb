module Attachments
  # PHOTOS FOR SEEDS, FROM LOCAL FILES — never from a network call.
  #
  # Hamma9900 saw the app live and every merchant card was an empty grey box
  # taking 60% of its height. The cause was not a defect: `Merchant` has `logo`
  # and `storefront_photo`, `CatalogItem` has `photo`, the serializer correctly
  # returns nil when nothing is attached — and NO SEED ATTACHED ANY OF THEM.
  #
  # Local fixtures, which is what `hatiwal-api/db/seeds/e2e.rb` does (read,
  # rather than assumed): seeding stays offline and deterministic, and a seed
  # that reaches the network fails on exactly the connection this product is
  # designed around.
  #
  # ── IN app/ RATHER THAN IN db/seeds.rb, and that is not tidiness ──────────
  # `spec/seeds/e2e_spec.rb` loads the seed FILES directly, so a helper defined
  # in `db/seeds.rb` would have to be shimmed in the spec — and a shimmed
  # helper means the spec never exercises the attaching. Autoloaded code is
  # real code: the seed spec now asserts that the photos actually arrive.
  #
  # ── WHAT THE IMAGES ARE, HONESTLY ────────────────────────────────────────
  # Generated warm cards, not photographs. Nobody here can photograph Afghan
  # food, and a downloaded stock burger would be worse than grey — he shows
  # this screen to restaurant owners in Kabul, and food from somewhere else
  # says the app was built for somewhere else.
  #
  # They carry no text, because Arabic-script shaping is unavailable on this
  # box and unjoined Pashto reads as broken rather than as untranslated — and
  # the app already renders the dish name beside the photo.
  #
  # **REPLACING THEM NEEDS NO CODE.** Drop real JPEGs over
  # `spec/fixtures/files/photos/<name>.jpg` and re-seed.
  module SeedPhoto
    DIRECTORY = "spec/fixtures/files/photos".freeze

    def self.attach!(record, attachment_name, file_name)
      return if file_name.blank?

      attachment = record.public_send(attachment_name)
      # Idempotent: seeds run repeatedly, and re-attaching on every run grows
      # storage without changing anything anybody can see.
      return if attachment.attached?

      path = Rails.root.join(DIRECTORY, file_name)
      # A missing file is SKIPPED rather than raised on: somebody replacing
      # these with their own photographs must not have a half-finished
      # directory stop the seed that populates everything else.
      unless path.exist?
        Rails.logger.info("[seed] no photo at #{path}")
        return
      end

      attachment.attach(io: path.open, filename: file_name, content_type: "image/jpeg")
    end
  end
end
