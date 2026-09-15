# Request rate limiting, on top of Rails' own ActionController::RateLimiting.
# No new gem and no middleware: limits are declared per action, next to the
# action they protect.
#
# ADAPTED FROM hatiwal-api's concern of the same name, including its reasoning,
# because the reasoning is the valuable part and it was learned there.
#
# Nothing limited anything here except OTP sends. These limits are deliberately
# far above real human use — they exist to stop automation, not to ration the
# app.
#
# Declaring a limit:
#
#   throttle to: 30, within: 1.day,  by: :user, only: :create
#   throttle to: 60, within: 1.hour, by: :ip,   only: :create
#
# Choosing `by:`
#   :user keys on the authenticated person, and is right for anything behind
#   authentication — one abusive account cannot spend anyone else's quota.
#   :ip is only for the endpoints that hand out the session in the first place,
#   where there is no user yet.
#
# **KEEP IP LIMITS GENEROUS.** Mobile users in Afghanistan sit behind
# carrier-grade NAT, so a whole city can share one address. An IP limit tight
# enough to be interesting is also tight enough to lock out a real
# neighbourhood — and every user here arrived through a conversation somebody
# had in person, so locking one out is expensive in a way a rate limit graph
# will never show.
module RateLimitable
  extend ActiveSupport::Concern

  # Rate limiting needs a cache store that can INCREMENT. Production uses
  # solid_cache (shared across Puma workers, which is what makes a limit real);
  # the test environment defaults to :null_store, whose increment always returns
  # nil — that would make every limit a silent no-op AND impossible to test,
  # which is the vacuously-green trap this project has already hit four times.
  # So tests get a dedicated in-memory store, cleared between examples.
  def self.store
    @store ||= Rails.env.test? ? ActiveSupport::Cache::MemoryStore.new : Rails.cache
  end

  class_methods do
    def throttle(to:, within:, by: :ip, **options)
      raise ArgumentError, "throttle by: must be :ip or :user" unless [ :ip, :user ].include?(by)

      rate_limit(
        to: to,
        within: within,
        store: RateLimitable.store,
        # Rails requires an explicit name once a controller carries more than
        # one limit; deriving it keeps two limits on one controller from sharing
        # a counter.
        name: "#{by}-#{to}-per-#{within.to_i}",
        by: -> { rate_limit_key(by) },
        with: -> { render_too_many_requests },
        **options
      )
    end
  end

  private

  # Wrapped so that a limiter can never be the reason a request fails.
  #
  # This concern is the first thing in the app to touch Rails.cache at all —
  # before it, a cache outage was completely harmless. It has to stay harmless:
  # an unreachable solid_cache database must not turn sign-in into a 500. So it
  # FAILS OPEN — the request is allowed through and the error is reported.
  # Losing a limit for the duration of a cache outage is the cheaper failure by
  # a wide margin.
  def rate_limiting(...)
    super
  rescue StandardError => e
    Rails.error.report(e, handled: true, severity: :warning, context: { rate_limit: controller_path })
    nil
  end

  # Falls back to the IP when a :user limit somehow runs without a signed-in
  # user (a filter ordering change, an optionally-authenticated endpoint) so the
  # limit keeps counting instead of lumping every anonymous caller under one nil
  # key.
  def rate_limit_key(by)
    return "ip:#{request.remote_ip}" if by == :ip

    current_user ? "user:#{current_user.id}" : "ip:#{request.remote_ip}"
  end

  def render_too_many_requests
    # A machine-readable code, because the app renders its own Pashto or Dari
    # message. A server-written English sentence is untranslatable on a device.
    render json: {
      error: "too many requests", code: "rate_limited"
    }, status: :too_many_requests
  end
end
