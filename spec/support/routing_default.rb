# ROUTED DISTANCE IS THE PRODUCTION DEFAULT; the SUITE opts in per example.
#
# `Setting::DEFINITIONS` now defaults `routing_distance_source` to `osrm`,
# because Hamma9900 decided distances are measured by roads and a default that
# contradicts the decision means the next fresh database silently reverts it.
#
# In specs that default would mean every quote reaches for the router. It would
# not BREAK anything — the client degrades and the resolver falls back — but
# hundreds of examples would then be exercising the failure path while
# appearing to test the happy one, and that is the shape of vacuous test this
# project keeps finding.
#
# So the row is written per example, and the examples that care about routing
# set it to `osrm` themselves (`enable_osrm!`). The DEFINITION's default is
# asserted separately, in spec/models/setting_spec.rb — the decision is tested
# where it is declared, not by making the whole suite behave as production.
RSpec.configure do |config|
  config.before do
    Setting.find_or_create_by!(key: "routing_distance_source") do |setting|
      setting.value = Routing::Route::STRAIGHT_LINE
      setting.value_type = :string
    end
  end
end
