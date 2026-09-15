# Counts must not leak between examples, or the twentieth spec to hit an
# endpoint fails for a reason that has nothing to do with it — and the failure
# would look like a flaky suite rather than a shared counter.
RSpec.configure do |config|
  config.before { RateLimitable.store.clear }
end
