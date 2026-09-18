require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
# Needed by Administrate, which renders HTML. An --api app omits it.
require "action_view/railtie"
require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module KarwanApi
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    # `middleware` is ignored because a Rack middleware must be a real constant
    # while the stack is being BUILT, and autoloading during boot is not
    # supported — `config/environments/development.rb` requires it explicitly.
    config.autoload_lib(ignore: %w[assets tasks middleware])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # KABUL, AND IT IS A CORRECTNESS SETTING RATHER THAN A DISPLAY ONE.
    #
    # Left unset, Rails runs in UTC and every "today" in this app meant the UTC
    # day — which in Kabul runs **04:30 to 04:30**, because the offset is +4:30.
    # Three figures are computed from `Time.zone.now.beginning_of_day`: the
    # merchant's day (PRODUCT.md:80 — orders, items sold, cash received, our
    # commission), the courier's day, and the console's commission-today. All
    # three answered a question nobody asked.
    #
    # The sharp end is a shop trading past midnight: an order at 01:00 Kabul
    # fell into the PREVIOUS day's figures, so a restaurant's late trade
    # belonged to yesterday while it was still being cooked.
    #
    # One city, one zone (CLAUDE.md: one neighbourhood in Kabul). Timestamps are
    # stored in UTC either way — this changes what a DAY means, not what is
    # written down.
    config.time_zone = "Kabul"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    # ---- Middleware Administrate needs, which api_only strips out ----------
    #
    # All four of these are lifted from hatiwal-api, where each one was added
    # after the symptom it causes. Keeping the comments because the symptoms
    # are not guessable from the code.

    # Devise (for AdminUser) references the session, which api_only removes —
    # without it every protected admin page raises
    # ActionDispatch::Request::Session::DisabledSessionError.
    config.session_store :cookie_store, key: "_karwan_admin_session"
    config.middleware.use ActionDispatch::Cookies
    config.middleware.use config.session_store, config.session_options

    # Administrate shows flash messages on top of the session above. The JSON
    # API never uses flash, so this only affects the admin views.
    config.middleware.use ActionDispatch::Flash

    # Administrate's edit/update/destroy and the sign-out button submit HTML
    # forms that tunnel PATCH/PUT/DELETE through POST plus a `_method` param.
    # api_only omits Rack::MethodOverride, so those verbs never reach the
    # router. The JSON API uses real verbs and is unaffected.
    config.middleware.use Rack::MethodOverride

    # Devise inserts Warden::Manager early in the api_only stack — ahead of the
    # session middleware re-added above. Normal requests survive because the
    # session is populated by the time a controller calls `set_user`, but
    # Warden's test `login_as` sets the user on the way IN, before the session
    # exists, which breaks :timeoutable. Move Warden after session and flash so
    # it always has a session to read.
    config.middleware.move_after ActionDispatch::Flash, Warden::Manager
  end
end
