module Attachments
  # AN ABSOLUTE URL, BECAUSE THE CONSUMER IS A NATIVE APP.
  #
  # Every serializer returned `rails_blob_path(..., only_path: true)` — a
  # host-relative path like `/rails/active_storage/blobs/...`. A browser
  # resolves that against its origin. **A native `<Image source={{ uri }}>` has
  # no origin**, so it resolves nothing and renders nothing.
  #
  # ── WHY THIS HAD NEVER BEEN NOTICED ──────────────────────────────────────
  # No seed attached a photo, so no photo URL had ever been produced. The first
  # real photograph would have rendered as an empty box — **identical to the
  # empty box that exists when there is no photo at all**, which is the worst
  # possible way for a bug to hide: its symptom is the state it replaces.
  #
  # ── WHY THE SERVER AND NOT THE CLIENT ────────────────────────────────────
  # The app knows its own base URL and could prefix the path itself. But a URL
  # that only works after client-side surgery is a contract that depends on
  # every client behaving, and correction 18 says four apps may consume this
  # API one day. The server owns the address of its own files.
  #
  # ── WHERE THE HOST COMES FROM ────────────────────────────────────────────
  # `APP_BASE_URL` when set, then the Kamal deploy host, then localhost for
  # development. NOT from the request: a serializer that reads the request
  # cannot be used from a job, a console or a seed — and the merchant alert
  # already builds payloads outside any request.
  module PublicUrl
    class << self
      # Nil when nothing is attached, which every caller already handles: a URL
      # to nothing is the same lie as a boolean claiming a file exists.
      # `variant:` names a variant DECLARED ON THE MODEL. Without one the
      # original blob is served, which is what every attachment in this app did
      # until 2026-09-18 — see docs/NOTES.md: a merchant card carries two
      # images, the default page is 20, and our own cap is 5 MB per image, so
      # one Home screen could pull 200 MB of originals to render them at about
      # 96 px. On a metered Kabul connection that is the user's own money.
      #
      # The URL is LAZY. `rails_representation_path` does not process anything;
      # the variant is generated on first fetch and cached thereafter. So this
      # works on a box with no libvips (which is every dev box here) and the
      # production image has libvips in both stages.
      #
      # FAILS OPEN to the original when the blob cannot be varied — an audio
      # note, or a type Active Storage will not process. A missing thumbnail
      # must never mean a missing photo.
      def for(attachment, variant: nil)
        return nil if attachment.nil? || !attachment.attached?

        path =
          if variant && attachment.blob.variable? && variants_processable?
            Rails.application.routes.url_helpers
                 .rails_representation_path(attachment.variant(variant), only_path: true)
          else
            Rails.application.routes.url_helpers.rails_blob_path(attachment, only_path: true)
          end
        "#{base_url}#{path}"
      end

      def base_url
        explicit = ENV["APP_BASE_URL"].presence
        return explicit.chomp("/") if explicit

        kamal_host = ENV["KAMAL_HOST"].presence
        return "https://#{kamal_host}" if kamal_host

        # Development and test. The port is the one `config/puma.rb` picks, not
        # Rails' 3000 — another app on this box holds 3000, which cost a
        # morning once.
        "http://localhost:#{ENV.fetch('PORT', 3017)}"
      end

      # ── CAN THIS MACHINE ACTUALLY MAKE A VARIANT? ────────────────────────
      #
      # `rails_representation_path` is LAZY: it returns a URL and processes on
      # first fetch. So a box with no image library serves a URL that 500s when
      # a phone asks for it — and the phone shows a broken image where an
      # unresized one used to work.
      #
      # That is exactly what happened on 2026-09-18. The variants shipped, the
      # production image has `libvips` in both Dockerfile stages, and the DEV
      # box has neither libvips nor an ImageMagick binary — so the device
      # testing against dev got broken images from a change that is correct in
      # production. A regression introduced by an optimisation, visible only on
      # the machine nobody deploys.
      #
      # So this degrades to the ORIGINAL rather than serving a URL that cannot
      # be fulfilled. Same posture the rest of this method already takes: a
      # missing thumbnail must never mean a missing photo. Memoised because the
      # answer cannot change inside a process.
      #
      # `bin/preflight` FAILS a deployed box on this, because there the fallback
      # is not a kindness — it is every phone downloading camera frames.
      def variants_processable?
        return @variants_processable if defined?(@variants_processable)

        @variants_processable = begin
          case Rails.application.config.active_storage.variant_processor
          when :vips then require "vips" && true
          when :mini_magick then require "mini_magick" && MiniMagick.cli.present?
          else false
          end
        rescue LoadError, StandardError
          false
        end
      end

      # Whether the address is configured rather than inferred. `bin/preflight`
      # asks, because a deployed API serving `http://localhost` photo URLs would
      # look correct in every log and show nothing on every phone.
      def configured?
        ENV["APP_BASE_URL"].present? || ENV["KAMAL_HOST"].present?
      end
    end
  end
end
