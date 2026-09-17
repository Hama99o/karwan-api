require "rails_helper"
require Rails.root.join("lib/middleware/pending_migration_json")

# Driven as a RACK APP rather than through a request spec, and that is the
# point rather than a convenience.
#
# `ActiveRecord::Migration::CheckPending` is only in the stack when
# `migration_error` is set, which is development only — so a request spec would
# exercise a stack this middleware is not in, go green, and prove nothing. That
# is the exact failure this repo keeps writing down: a test that agrees with
# itself against a path the code never takes.
#
# Driving it directly also means no migration file on disk, no orphan
# `schema_migrations` row, and nothing taken down — creating the real condition
# would 500 the shared development API for every session on this box, which is
# the bug this exists to explain.
RSpec.describe PendingMigrationJson do
  let(:error) { ActiveRecord::PendingMigrationError.new("Migrations are pending.\nrun bin/rails db:migrate") }
  let(:failing_app) { ->(_env) { raise error } }
  let(:healthy_app) { ->(_env) { [ 200, {}, [ "ok" ] ] } }

  def call(app, path: "/api/v1/public/merchants")
    described_class.new(app).call("PATH_INFO" => path, "REQUEST_METHOD" => "GET")
  end

  it "passes a healthy request straight through" do
    status, _headers, body = call(healthy_app)

    expect(status).to eq(200)
    expect(body).to eq([ "ok" ])
  end

  describe "when a migration is pending" do
    it "answers 503 — not ready, rather than broken" do
      status, = call(failing_app)

      expect(status).to eq(503)
    end

    it "answers JSON, which is the whole point in an api_only app" do
      _status, headers, body = call(failing_app)

      expect(headers["Content-Type"]).to eq("application/json")
      expect { JSON.parse(body.first) }.not_to raise_error
    end

    it "carries a machine-readable code a probe can branch on" do
      _status, _headers, body = call(failing_app)

      expect(JSON.parse(body.first)["code"]).to eq("pending_migration")
    end

    # The whole cost of the original incident was a symptom that named nothing.
    it "states the remedy, because the operator knows it and the reader may not" do
      _status, _headers, body = call(failing_app)

      expect(JSON.parse(body.first)["remedy"]).to eq("bin/rails db:prepare")
    end

    # ── THE HEADLINE PROPERTY, AND IT NEARLY SHIPPED UNTESTED ────────────────
    #
    # Everything else above would be satisfied by a 503 saying "not ready".
    # NAMING the migration is the reason this exists: the original hour was
    # lost to a symptom that named nothing, and a session that did not write
    # the migration could not tell whose it was.
    #
    # The versions are stubbed because the real condition cannot be created —
    # a migration file on disk takes the shared development API down for every
    # session on this box. The stub stands in for the OUTSIDE WORLD (what the
    # database has recorded), never for the subject: the mapping from versions
    # to filenames is the code under test and runs for real.
    it "names the pending migration, which is the reason it exists" do
      context = ActiveRecord::Base.connection_pool.migration_context
      real = context.migrations.last
      allow_any_instance_of(ActiveRecord::MigrationContext)
        .to receive(:pending_migration_versions).and_return([ real.version ])

      _status, _headers, body = call(failing_app)

      expect(JSON.parse(body.first)["migrations"])
        .to eq([ File.basename(real.filename, ".rb") ])
    end

    it "still answers when it cannot work out which migration it was" do
      allow_any_instance_of(ActiveRecord::MigrationContext)
        .to receive(:pending_migration_versions).and_raise(StandardError, "no database")

      status, _headers, body = call(failing_app)
      parsed = JSON.parse(body.first)

      expect(status).to eq(503)
      expect(parsed["code"]).to eq("pending_migration")
      expect(parsed).not_to have_key("migrations")
    end

    it "is not cached, because it stops being true the moment it is fixed" do
      _status, headers, = call(failing_app)

      expect(headers["Cache-Control"]).to eq("no-store")
    end

    # ── `/up` IS EXEMPT, AND THAT IS A DECISION ──────────────────────────────
    #
    # If the health endpoint failed with everything else, a probe could not tell
    # "the API process is not running" from "the API is running and unmigrated"
    # — and that ambiguity is the hour this middleware exists to prevent.
    # Asserted so it cannot drift silently.
    it "lets /up fail the way it always did, so a probe can tell the two apart" do
      expect { call(failing_app, path: "/up") }
        .to raise_error(ActiveRecord::PendingMigrationError)
    end
  end

  # ── THE HALF THE UNIT TEST ABOVE CANNOT SEE ──────────────────────────────
  #
  # Every example above would pass with the middleware never inserted into any
  # stack. Asserted as source shape for the reason spec/config/preflight_spec.rb
  # states — a spec must not boot a second environment — and the real ordering
  # was verified by running it when this landed:
  #
  #   ["PendingMigrationJson", "ActiveRecord::Migration::CheckPending"]
  #
  # which is the order that matters: this must wrap `CheckPending` to rescue
  # what it raises.
  describe "the wiring" do
    let(:source) { Rails.root.join("config/environments/development.rb").read }

    it "is inserted before the middleware whose error it answers" do
      expect(source).to include(
        "config.middleware.insert_before ActiveRecord::Migration::CheckPending"
      )
      expect(source).to include("PendingMigrationJson")
    end

    # It cannot be autoloaded — the stack is built during boot — so the require
    # and the ignore list have to stay in step.
    it "is required rather than autoloaded, and excluded from autoload_lib" do
      expect(source).to include('require Rails.root.join("lib/middleware/pending_migration_json")')
      expect(Rails.root.join("config/application.rb").read)
        .to include("config.autoload_lib(ignore: %w[assets tasks middleware])")
    end

    # DEVELOPMENT ONLY, and the commit says so — `CheckPending` is not in the
    # production stack, so nothing in production returns this 503. If this
    # assertion ever fails, somebody has moved it to a shared config and
    # `insert_before` will raise at boot.
    it "lives in development, where the middleware it wraps actually exists" do
      expect(Rails.root.join("config/environments/production.rb").read)
        .not_to include("PendingMigrationJson")
    end
  end
end
