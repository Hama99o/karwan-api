# WHAT A PHONE PAYS FOR ON A POLL IS MOSTLY HEADERS.
#
# karwan-42 measured it at the production layer (bin/thrust, 25 Sept 2026):
# the courier's offer poll has a 14-byte body and about 440 bytes of
# response, so gzip saves nothing there and a 304 saves 71. Of what was left,
# six headers instruct a BROWSER rendering a DOCUMENT, or exist for
# debugging. A native client reading JSON uses none of them. At a poll every
# few seconds, on metered data, that is a real share of a shift's bill.
#
# Enumerated from what a response ACTUALLY carried (a probe of
# GET /api/v1/courier/offer), not from the middleware list:
#
#   DROPPED on /api:
#     x-frame-options                    framing, which only a browser does
#     x-xss-protection                   a legacy browser filter (value "0")
#     x-permitted-cross-domain-policies  Flash and PDF readers
#     referrer-policy                    documents that navigate
#     x-runtime                          a debugging convenience
#     x-request-id                       still generated and still in every
#                                        log line (`log_tags`); no client
#                                        reads it from the response
#   KEPT:
#     x-content-type-options: nosniff    an API URL opened in a browser must
#                                        never be sniffed as HTML
#     etag, cache-control                the 304s depend on them
#     content-type, content-length
#
# ONLY /api. The same app serves the Administrate console to a real browser,
# where x-frame-options is load-bearing: a money console in a frame is a
# clickjacking target. So the defaults stay global and this removes them
# from JSON answers alone.
#
# `require`d from config/application.rb rather than autoloaded, like
# PendingMigrationJson: the stack is built during boot.
class ApiHeaderDiet
  DROPPED = %w[
    x-frame-options x-xss-protection x-permitted-cross-domain-policies
    referrer-policy x-runtime x-request-id
  ].freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)
    DROPPED.each { |name| headers.delete(name) } if env["PATH_INFO"].to_s.start_with?("/api/")
    [ status, headers, body ]
  end
end
