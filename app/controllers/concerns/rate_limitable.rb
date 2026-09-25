# Request rate limiting. No new gem and no middleware: limits are declared per
# action, next to the action they protect. (It began on Rails' own
# `rate_limit`, which cannot say when a window ends — see `Window`.)
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
#   where there is no user yet — and even there it is a BACKSTOP. Sign-in's
#   real limit is per identifier (`Api::V1::Auth::SessionsController`),
#   because the thing being guessed is one account's password, not an
#   address's.
#
# **KEEP IP LIMITS GENEROUS.** Mobile users in Afghanistan sit behind
# carrier-grade NAT, so a whole city can share one address. An IP limit tight
# enough to be interesting is also tight enough to lock out a real
# neighbourhood — and every user here arrived through a conversation somebody
# had in person, so locking one out is expensive in a way a rate limit graph
# will never show.
module RateLimitable
  extend ActiveSupport::Concern

  # Rate limiting needs a cache store that can INCREMENT. **Production does NOT
  # use solid_cache**, whatever this line said until 25 Sept 2026:
  # `config/environments/production.rb` sets no `cache_store`, so Rails' default
  # applies, a FileStore under the container's `tmp/cache`. That counts
  # correctly for ONE web container (FileStore locks around increment), resets
  # on every deploy, and would NOT be shared by a second container. Recorded in
  # docs/NOTES.md;
  # the test environment defaults to :null_store, whose increment always returns
  # nil — that would make every limit a silent no-op AND impossible to test,
  # which is the vacuously-green trap this project has already hit four times.
  # So tests get a dedicated in-memory store, cleared between examples.
  def self.store
    @store ||= Rails.env.test? ? ActiveSupport::Cache::MemoryStore.new : Rails.cache
  end

  # ── A FIXED WINDOW, SO THE REFUSAL CAN SAY HOW LONG ───────────────────────
  #
  # This used to hand straight to Rails' `rate_limit`, which counts under a key
  # that expires `within` after its first hit and never says when that is. So
  # every 429 here was "too many requests" with no time in it — the dead end
  # the OTP controller's own comment warns about ("with no indication of when
  # to try again is the dead end that loses a first-time user"). A window
  # anchored to the clock (`now / within`) knows its own end, which is the
  # number `retry_after_seconds` carries.
  #
  # The trade: a fixed window lets a burst of up to 2× through across a
  # boundary. For limits that exist to stop automation, far above human use,
  # that is not a difference anybody can exploit into harm.
  class Window
    def initialize(store:, key:, within:, now: Time.current)
      @store = store
      @within = within.to_i
      @index = now.to_i / @within
      @key = "#{key}:#{@index}"
      @now = now
    end

    # Counts this request and returns the count so far in the window.
    def hit!
      @store.increment(@key, 1, expires_in: @within + 1)
    end

    # The count so far, without counting.
    def count
      @store.read(@key, raw: true).to_i
    end

    def retry_after_seconds
      ((@index + 1) * @within - @now.to_i).clamp(1, @within)
    end
  end

  class_methods do
    def throttle(to:, within:, by: :ip, **options)
      raise ArgumentError, "throttle by: must be :ip or :user" unless [ :ip, :user ].include?(by)

      # Deriving the name keeps two limits on one controller from sharing a
      # counter.
      name = "#{by}-#{to}-per-#{within.to_i}"
      before_action(-> { enforce_throttle(to: to, within: within, by: by, name: name) }, **options)
    end
  end

  private

  def enforce_throttle(to:, within:, by:, name:)
    window = rate_limit_window(["rate-limit", controller_path, name, rate_limit_key(by)].join(":"), within)
    count = rate_limit_safely { window.hit! }
    render_too_many_requests(window.retry_after_seconds) if count && count > to
  end

  def rate_limit_window(key, within)
    Window.new(store: RateLimitable.store, key: key, within: within)
  end

  # Wrapped so that a limiter can never be the reason a request fails.
  #
  # This concern is the first thing in the app to touch Rails.cache at all —
  # before it, a cache outage was completely harmless. It has to stay harmless:
  # an unreachable solid_cache database must not turn sign-in into a 500. So it
  # FAILS OPEN — the request is allowed through and the error is reported.
  # Losing a limit for the duration of a cache outage is the cheaper failure by
  # a wide margin.
  def rate_limit_safely
    yield
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

  # A machine-readable code, because the app renders its own Pashto or Dari
  # message. A server-written English sentence is untranslatable on a device.
  #
  # AND A NUMBER, in the body and in the standard header, so "wait" can become
  # "wait four minutes". `code` is unchanged, so an app that only knows
  # `rate_limited` keeps rendering what it renders today.
  def render_too_many_requests(retry_after_seconds)
    response.set_header("Retry-After", retry_after_seconds.to_s)
    render json: {
      error: "too many requests", code: "rate_limited",
      retry_after_seconds: retry_after_seconds
    }, status: :too_many_requests
  end
end
