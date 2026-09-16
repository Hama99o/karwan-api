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
      def for(attachment)
        return nil if attachment.nil? || !attachment.attached?

        path = Rails.application.routes.url_helpers.rails_blob_path(attachment, only_path: true)
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

      # Whether the address is configured rather than inferred. `bin/preflight`
      # asks, because a deployed API serving `http://localhost` photo URLs would
      # look correct in every log and show nothing on every phone.
      def configured?
        ENV["APP_BASE_URL"].present? || ENV["KAMAL_HOST"].present?
      end
    end
  end
end
