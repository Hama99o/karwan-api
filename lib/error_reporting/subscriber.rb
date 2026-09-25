# EVERY ERROR RAILS REPORTS: LOGGED FIRST, THEN KEPT (launch readiness A6).
#
# Rails already reports every unhandled request error (ActionDispatch::Executor)
# and every job error to `Rails.error`. Until 25 Sept 2026 nothing subscribed,
# so they went only to the container's log.
#
# ── THE ORDER IS THE DESIGN ─────────────────────────────────────────────────
#
# 1. LOG, unconditionally, one greppable line: `[error-report] …`. It needs
#    nothing but STDOUT, so it still works when Postgres is the thing that
#    failed, which is the outage you most want reported.
# 2. PERSIST to `error_reports`, as a second step that is ALLOWED TO FAIL. If
#    it raises, that is logged too and swallowed: a reporter must never turn
#    one error into two, or take the request down with it.
#
# Both carry only redacted text (ErrorReport::Redaction), so the log line is
# as safe to paste as the row.
#
# `require`d by config/initializers/error_reporting.rb; lib/error_reporting is
# on autoload_lib's ignore list, like lib/middleware. ErrorReport is looked up
# at report time, so code reloading in development is unaffected.
module ErrorReporting
  class Subscriber
    TAG = "[error-report]".freeze

    def report(error, handled:, severity:, context: {}, source: nil)
      log(error, handled: handled, severity: severity, source: source)
      persist(error, handled: handled, severity: severity, context: context, source: source)
    end

    private

    def log(error, handled:, severity:, source:)
      Rails.logger.error(
        "#{TAG} #{error.class.name} severity=#{severity} handled=#{handled} source=#{source} " \
        "message=#{ErrorReport::Redaction.message(error.message).inspect}"
      )
    rescue StandardError
      nil # a broken logger must not take the request down either
    end

    def persist(error, handled:, severity:, context:, source:)
      ErrorReport.record!(error, handled: handled, severity: severity, context: context, source: source)
    rescue StandardError => e
      Rails.logger.error("#{TAG} could not be kept (#{e.class}); the line above is the only record")
      nil
    end
  end
end
