# This file is copied to spec/ when you run 'rails generate rspec:install'
require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
# Prevent database truncation if the environment is production
abort("The Rails environment is running in production mode!") if Rails.env.production?
# Uncomment the line below in case you have `--require rails_helper` in the `.rspec` file
# that will avoid rails generators crashing because migrations haven't been run yet
# return unless Rails.env.test?
require 'rspec/rails'
# Add additional requires below this line. Rails is not loaded until this point!

# Requires supporting ruby files with custom matchers and macros, etc, in
# spec/support/ and its subdirectories. Files matching `spec/**/*_spec.rb` are
# run as spec files by default. This means that files in spec/support that end
# in _spec.rb will both be required and run as specs, causing the specs to be
# run twice. It is recommended that you do not name files matching this glob to
# end with _spec.rb. You can configure this pattern with the --pattern
# option on the command line or in ~/.rspec, .rspec or `.rspec-local`.
#
# The following line is provided for convenience purposes. It has the downside
# of increasing the boot-up time by auto-requiring all files in the support
# directory. Alternatively, in the individual `*_spec.rb` files, manually
# require only the support files necessary.
#
# ══ ONE RSPEC PER DATABASE — ENFORCED, NOT REMEMBERED ══════════════════════
#
# Two rspec processes against one test database do not queue politely.
# `database_cleaner` truncates while the other holds rows, and the damage lands
# on BOTH runs:
#
#   · the loser reports `0 examples, 0 failures, 1 error` — which announces
#     itself, and docs/TESTING.md calls it the fifth shape of a lying instrument
#   · the WINNER gets a spurious failing example in whatever spec was mid-flight
#     — which announces nothing, and **looks exactly like a regression**
#
# The second one is the expensive half. Measured on 2026-09-17: a targeted plant
# run started while a full suite was in flight produced one failing auth example
# that nothing had touched, and cost twenty-five minutes and four runs to prove
# innocent. Both processes were mine, on one session's own database — so the
# boundary is per PROCESS, not per session, and `TEST_DB_SUFFIX` alone does not
# reach it.
#
# A written rule does not help, because it has to be remembered at the exact
# moment somebody is mid-hunt and wants one quick targeted run. So the suite
# refuses instead.
#
# DELIBERATELY BEFORE THE SUPPORT GLOB: `spec/support/database_cleaner.rb`
# registers a `before(:suite)` that TRUNCATES, hooks run in registration order,
# and the truncation is the destructive act. Sorted alphabetically it would load
# first; required here, this lock is taken before anything can be destroyed.
#
# Uncontended in CI, where one runner holds it and nothing competes. The lock is
# session-scoped, so it is released when the process exits even if it crashes.
EXCLUSIVE_DATABASE_LOCK_KEY = Zlib.crc32(
  ActiveRecord::Base.connection_db_config.database.to_s
).freeze

RSpec.configure do |config|
  config.before(:suite) do
    database = ActiveRecord::Base.connection_db_config.database
    acquired = ActiveRecord::Base.connection.select_value(
      "SELECT pg_try_advisory_lock(#{EXCLUSIVE_DATABASE_LOCK_KEY})"
    )

    unless [ true, "t" ].include?(acquired)
      # `exit!` rather than `abort`, and this matters: `abort` raises
      # SystemExit, RSpec's before(:suite) swallows it, and the run then
      # reports `0 examples, 0 failures` and exits 0 — **a refusal that looks
      # like a pass**, which is the exact shape this guard exists to prevent.
      # Measured: the first version of this did precisely that. `exit!` leaves
      # immediately with a non-zero status and no further RSpec output.
      $stderr.puts <<~REFUSED

        ✗ ANOTHER RSPEC IS ALREADY RUNNING AGAINST `#{database}`.

          Refusing to start. Results from a shared test database are not
          trustworthy in either direction: this run would report
          `0 examples … 1 error`, and the run already in flight would get a
          spurious failing example that looks exactly like a regression.

          Wait for it, or give this process its own database:
            TEST_DB_SUFFIX=_xx RAILS_ENV=test bin/rails db:prepare
            TEST_DB_SUFFIX=_xx bundle exec rspec

          See docs/TESTING.md, "one test database per session".
      REFUSED

      exit!(1)
    end

    # Only a run that TOOK the lock may release it. Releasing one we never held
    # makes Postgres warn "you don't own a lock of type ExclusiveLock", which
    # is noise that reads like a real problem.
    @holds_exclusive_database_lock = true
  end

  config.after(:suite) do
    next unless @holds_exclusive_database_lock

    ActiveRecord::Base.connection.select_value(
      "SELECT pg_advisory_unlock(#{EXCLUSIVE_DATABASE_LOCK_KEY})"
    )
  rescue StandardError
    # The process is exiting and the lock dies with the session anyway. A
    # failure to release must never turn a green suite red.
    nil
  end
end

Rails.root.glob('spec/support/**/*.rb').sort_by(&:to_s).each { |f| require f }

# Ensures that the test database schema matches the current schema file.
# If there are pending migrations it will invoke `db:test:prepare` to
# recreate the test database by loading the schema.
# If you are not using ActiveRecord, you can remove these lines.
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end
RSpec.configure do |config|
  # Remove this line if you're not using ActiveRecord or ActiveRecord fixtures
  config.fixture_paths = [
    Rails.root.join('spec/fixtures')
  ]

  # If you're not using ActiveRecord, or you'd prefer not to run each of your
  # examples within a transaction, remove the following line or assign false
  # instead of true.
  config.use_transactional_fixtures = true

  # You can uncomment this line to turn off ActiveRecord support entirely.
  # config.use_active_record = false

  # RSpec Rails uses metadata to mix in different behaviours to your tests,
  # for example enabling you to call `get` and `post` in request specs. e.g.:
  #
  #     RSpec.describe UsersController, type: :request do
  #       # ...
  #     end
  #
  # The different available types are documented in the features, such as in
  # https://rspec.info/features/8-0/rspec-rails
  #
  # You can also infer these behaviours automatically by location, e.g.
  # /spec/models would pull in the same behaviour as `type: :model` but this
  # behaviour is considered legacy and will be removed in a future version.
  #
  # To enable this behaviour uncomment the line below.
  # config.infer_spec_type_from_file_location!

  # Filter lines from Rails gems in backtraces.
  config.filter_rails_from_backtrace!
  # arbitrary gems may also be filtered via:
  # config.filter_gems_from_backtrace("gem name")
end
