# ONE ROW PER DISTINCT ERROR, counted (launch readiness A6, 25 Sept 2026).
#
# Before this, a checkout 500 existed only in a container log: it survived
# until the next deploy and was seen only by whoever went looking. A hosted
# service (Sentry and friends) would send Afghan customers' request data to a
# company he hasn't chosen, and costs money: that is his call. This is the
# half that is ours. Nothing leaves the box, and it is the seam a hosted
# service would plug into later (another `Rails.error` subscriber).
#
# Written by `ErrorReporting::Subscriber`, which LOGS FIRST and persists
# second, so a database outage is still reported (to the log).
class ErrorReport < ApplicationRecord
  # Retention, enforced by `PruneErrorReportsJob` (config/recurring.yml), not
  # by this comment. The box's disk has been at 92-97%.
  KEEP_FOR = 30.days
  KEEP_AT_MOST = 500

  BACKTRACE_LINES = 12

  scope :newest_first, -> { order(last_seen_at: :desc, id: :desc) }

  # Records one occurrence: a new row, or +1 on the row with the same
  # fingerprint. One statement, so two workers reporting the same error at
  # once can't lose a count.
  def self.record!(error, handled:, severity:, context: {}, source: nil, at: Time.current)
    frames = Redaction.backtrace(error.backtrace)
    row = {
      fingerprint: fingerprint_for(error, frames),
      error_class: error.class.name.to_s,
      message: Redaction.message(error.message),
      backtrace: frames.join("\n"),
      source: source.to_s.presence,
      severity: severity.to_s,
      handled: handled ? true : false,
      context: Redaction.context(context),
      occurrences: 1,
      first_seen_at: at,
      last_seen_at: at
    }

    upsert(row, unique_by: :fingerprint,
                on_duplicate: Arel.sql(<<~SQL.squish))
                  occurrences = error_reports.occurrences + 1,
                  last_seen_at = EXCLUDED.last_seen_at,
                  message = EXCLUDED.message,
                  context = EXCLUDED.context,
                  handled = EXCLUDED.handled,
                  severity = EXCLUDED.severity
                SQL
  end

  # The error's own identity: its class and the first frame in OUR code,
  # without the line number (lines move with every edit) and never the
  # message (which carries ids and values that differ per occurrence).
  def self.fingerprint_for(error, frames)
    first_own = frames.find { |f| f.start_with?("app/", "lib/") } || frames.first.to_s
    where = first_own.sub(/:\d+:in /, ":in ")
    Digest::SHA256.hexdigest("#{error.class.name}|#{where}")[0, 32]
  end

  def self.prune!(now: Time.current)
    where(last_seen_at: ...(now - KEEP_FOR)).delete_all
    keep = newest_first.limit(KEEP_AT_MOST).select(:id)
    where.not(id: keep).delete_all
  end
end
