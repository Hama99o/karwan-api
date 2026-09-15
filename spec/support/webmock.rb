require "webmock/rspec"

# Real HTTP is disabled in the suite. OSRM is the only outbound call in the app,
# and a spec that silently reached a live router would pass on this machine and
# fail in CI — or worse, pass in CI against nothing.
WebMock.disable_net_connect!(allow_localhost: false)
