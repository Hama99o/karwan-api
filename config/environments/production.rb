require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  # config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  # config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  # config.cache_store = :mem_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # ── OUTGOING MAIL: SMTP, EVERY VALUE FROM A VARIABLE ─────────────────────
  #
  # Hamma9901 asked which provider. The answer is DELIBERATELY NONE: plain
  # SMTP, with the host, port, user and password all from the environment, so
  # picking a provider later is four env vars rather than a gem, a deploy and a
  # keyed API. `hatiwal-api/config/environments/production.rb` does the same
  # thing (read, per correction 15) with its credentials store; the only change
  # here is ENV rather than credentials, because Hamma9900's standing
  # instruction is that every host and credential comes from a variable so the
  # server that does not exist yet is five minutes of work.
  #
  # It also keeps correction 14 intact. A transactional-email SDK would be a
  # third keyed dependency with a bill; SMTP is a protocol, and the same config
  # points at a Postfix on his own VPS if he would rather not have one at all.
  #
  # WHAT MAIL IS ACTUALLY FOR HERE, so nobody over-invests: the ops console's
  # Devise reset, and the user password-reset CODE for the minority of accounts
  # that have an email at all. Phone is the guaranteed identifier
  # (docs/IDENTITY_AND_ROLES.md §1), so SMS — not email — is the channel that
  # has to work, and that is still waiting on the gateway Hamma9900 has to
  # choose.
  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.delivery_method = :smtp
  config.action_mailer.smtp_settings = {
    address: ENV.fetch("SMTP_ADDRESS", "localhost"),
    port: ENV.fetch("SMTP_PORT", 587).to_i,
    user_name: ENV["SMTP_USER_NAME"],
    password: ENV["SMTP_PASSWORD"],
    domain: ENV.fetch("SMTP_DOMAIN", "karwan.af"),
    authentication: :plain,
    enable_starttls_auto: true
  }.compact

  # Set host to be used by links generated in mailer templates.
  #
  # Present for the ops console's own Devise mail, which DOES link. The user
  # password reset deliberately does not: correction 16 means there is no web
  # page for a link to open, so that email carries a code the person types into
  # the app (Users::PasswordResetService).
  config.action_mailer.default_url_options = {
    host: ENV.fetch("APP_DOMAIN", "api.karwan.af"), protocol: "https"
  }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks.
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  #
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
