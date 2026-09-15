source "https://rubygems.org"

gem "rails", "~> 8.1.3"
gem "pg", "~> 1.1"
gem "puma", ">= 5.0"
gem "tzinfo-data", platforms: %i[ windows jruby ]
gem "bootsnap", require: false
gem "kamal", require: false
gem "thruster", require: false

# Pinned below 3.0. json 3.0 made JSON.parse's options KEYWORD-only, and
# Rails 8.1.3.1's Active Storage still passes them positionally when
# deserialising a blob's metadata column — so EVERY attachment upload raises
# "wrong number of arguments (given 2, expected 1)" from
# ActiveStorage::Blob#custom_metadata.
#
# That means photos, ID documents and address voice notes, which is most of what
# this app stores. Nothing surfaced it until a spec actually attached a file.
# Remove the pin when Rails supports json 3.
gem "json", "~> 2.21"

# Catalog item photos (Active Storage variants)
gem "image_processing", "~> 1.2"
gem "aws-sdk-s3", require: false

# Auth: phone + OTP, not email/password. See docs/AUTH.md — this is the one
# deliberate departure from hatiwal-api, which uses devise_token_auth on email.
# bcrypt digests the OTP codes and the session tokens; nothing stores either in
# the clear.
gem "bcrypt", "~> 3.1.7"

# Authorization
gem "pundit"

# Serialization
gem "blueprinter"

# Pagination — pinned to 8.x so hatiwal-api's `paginate_blue` (which passes
# Pagy's `:items` var explicitly) transfers verbatim.
gem "pagy", "~> 8.0"

# CORS
gem "rack-cors"

# Solid adapters (cache, queue, cable) — all Postgres-backed, so no Redis in v0
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Swagger API docs served at /api-docs (admin-gated in routes). Available in all
# environments so production can serve them; rswag-specs (below) stays in test
# for regenerating swagger.yaml from the request specs.
gem "rswag-api"
gem "rswag-ui"

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
  gem "bundler-audit", require: false

  # Testing
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "faker"
  gem "rswag-specs"
end

group :test do
  gem "shoulda-matchers"
  gem "database_cleaner-active_record"
  gem "webmock"
  gem "simplecov", require: false
end
