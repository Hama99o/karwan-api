# A PENDING MIGRATION SHOULD SAY SO, IN A LANGUAGE A CLIENT CAN READ.
#
# ── What this cost, which is why it exists ────────────────────────────────
#
# A migration generated in one session and not applied to `karwan_development`
# put `/api/v1/public/app_config` and `/api/v1/public/merchants` on HTTP 500
# for every session on this box, and blocked a 21-flow device run that had
# nothing to do with the schema. `check_pending_migrations` refuses every
# request including the pre-auth public ones, so from any other session the
# symptom is "the API is down" and names nothing. The QA rig's probe could
# only report the same.
#
# Rails already knows the answer — `migration_error = :page_load` renders its
# own error page naming the migration. That page is exactly right for a
# browser and useless to `config.api_only`: a JSON client gets a 500 whose
# body it cannot read.
#
# ── Why MIDDLEWARE and not `rescue_from` ──────────────────────────────────
#
# `ActiveRecord::Migration::CheckPending` raises BEFORE any controller exists,
# so a `rescue_from` in the API base controller would never fire — it would be
# dead code that tests green against a request that never reaches it, which is
# this repo's most-repeated failure. This sits one layer OUTSIDE `CheckPending`
# and rescues what it raises, so it needs no copy of the check itself: one
# implementation, and this only decides how the answer is phrased.
#
# ── 503, not 500 ──────────────────────────────────────────────────────────
#
# "Not ready", not "broken" — and it is the one failure where the operator
# knows the exact remedy, so the remedy goes in the body.
class PendingMigrationJson
  # `/up` IS DELIBERATELY EXEMPT, and the reason is the bug above rather than
  # a convention.
  #
  # If the health endpoint fails with everything else, a probe cannot tell "the
  # API process is not running" from "the API is running and unmigrated" — and
  # that ambiguity is the entire hour this middleware exists to prevent. Keeping
  # `/up` answering means `qa.sh doctor` can say which one it is.
  #
  # The cost is understood: Kamal health-checks `/up`, so an unmigrated
  # production container would pass its health check. That is not a regression
  # here, because this middleware is DEVELOPMENT-ONLY (see
  # config/environments/development.rb) — `CheckPending` is not even in the
  # production stack, where `db:migrate` runs as a deploy step instead. If it is
  # ever wanted in production, this exemption is the line to revisit first.
  EXEMPT = [ "/up" ].freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    @app.call(env)
  rescue ActiveRecord::PendingMigrationError => e
    raise if EXEMPT.include?(env["PATH_INFO"])

    [ 503,
      { "Content-Type" => "application/json", "Cache-Control" => "no-store" },
      [ body(e) ] ]
  end

  private

  def body(error)
    {
      error: "the database is behind the code — run the migrations",
      code: "pending_migration",
      # NAMED, because the whole cost of the original hour was a symptom that
      # named nothing. A session that did not write the migration can now see
      # whose it is.
      migrations: pending_migration_names,
      remedy: "bin/rails db:prepare",
      detail: error.message.to_s.lines.first.to_s.strip
    }.compact.to_json
  end

  # `pending_migration_versions`, verified against the real object rather than
  # remembered — the obvious-sounding `open_migrations` does not exist, and
  # `bin/preflight` carries a scar from this exact class of guess
  # (`connection.migration_context` raises `NoMethodError` and the script
  # reported it as "could not ask Rails").
  #
  # Best-effort: if asking costs an exception we still answer, because a
  # diagnostic that can fail is worse than a vague one. The `code` and the
  # remedy are the load-bearing parts and neither depends on this.
  def pending_migration_names
    context = ActiveRecord::Base.connection_pool.migration_context
    pending = context.pending_migration_versions
    return nil if pending.empty?

    context.migrations
           .select { |migration| pending.include?(migration.version) }
           .map { |migration| File.basename(migration.filename, ".rb") }
  rescue StandardError
    nil
  end
end
