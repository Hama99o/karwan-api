require "rails_helper"

# ═══ EVERY CONSOLE PAGE, FETCHED ═══════════════════════════════════════════
#
# Correction 1 puts the ops console inside this repo, and `PRODUCT.md` calls it
# *"the most important surface in v0 — what makes the business operable while
# everything else is half-built."* Two of its twenty-six dashboards were ever
# fetched by a spec: the landing page and the orders board.
#
# ── THREE WAYS AN ADMINISTRATE PAGE BREAKS WHILE LOOKING HEALTHY ──────────
#
# All three were measured in this repo on 21 Sept, not imagined:
#
#   1. A derived field whose method raises → **200**, the row label rendered and
#      the cell empty. `cash_in_hand` defined below `private` did exactly this,
#      and a check for the label passed.
#   2. A filter lambda that dies inside a `where` → **200 with zero rows**,
#      indistinguishable from a filter that matched nothing.
#   3. A filter lambda that raises outright → **500**, but only for whoever
#      clicks that one filter. `PricingRateDashboard`'s `deliveries` had been
#      doing this for as long as it existed.
#
# ── WHAT THIS ONE ACTUALLY CATCHES, WHICH IS THE THIRD ────────────────────
#
# A status check sees (3) and CANNOT see (1) or (2) — both render 200, which is
# the whole reason they are dangerous. Planting the private method back left
# this spec fully green, correctly.
#
# So the three are covered by three different assertions, and saying so here
# matters more than the coverage: a comment claiming this file guards all three
# would be the "title claims more than the body asserts" failure that
# `docs/TESTING.md` catalogues.
#
#   (1) empty cell  → a spec that PARSES THE VALUE of the field —
#                     `cash_in_hand_is_visible_spec.rb`
#   (2) zero rows   → `every_console_filter_runs_spec.rb`, which CALLS each
#                     lambda, so one that raises is caught before a page can
#                     swallow it
#   (3) 500         → this file, through the real request, across every page
#                     and every filter
#
# This is the only thing that fetches twenty-one of those pages at all, which is
# its own justification: `PricingRateDashboard`'s `deliveries` filter answered
# 500 for as long as it existed, and was found by accident rather than by a
# spec.
#
# ── DERIVED FROM THE DASHBOARDS, NOT A LIST ──────────────────────────────
#
# A hand-written list does not grow a row when somebody adds a resource —
# `authorization_boundary_spec` says the same and gives the same reason. The
# domain here is every dashboard on disk that the router actually exposes.
RSpec.describe "every ops console page opens", type: :request do
  let(:admin) { AdminUser.create!(name: "Ops", email: "sweep@karwan.af", password: "a-long-test-password") }

  before do
    post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
  end

  # ── A LOCAL, NOT A CONSTANT ────────────────────────────────────────────
  #
  # A constant in a describe block lands on `Object`. Written as `RESOURCES` it
  # collided with `dashboards_spec.rb`'s own `RESOURCES` and broke THAT file —
  # an array of Hashes where it expected strings, failing with "comparison of
  # Hash with Hash failed" in a spec I had not touched.
  #
  # `docs/TESTING.md` already records this shape from two gates that leaked
  # `SANCTIONED` the same way. A local is enough: the loop below runs at
  # definition time and nothing outside needs the value.
  console_indexes = Rails.application.routes.routes.filter_map do |route|
    next unless route.defaults[:controller].to_s.start_with?("admin/")
    next unless route.defaults[:action] == "index"

    path = route.path.spec.to_s.sub("(.:format)", "")
    next if path.include?(":")

    { path: path, controller: route.defaults[:controller] }
  end.uniq { |r| r[:path] }

  it "found the console's pages, or every example below is asserting nothing" do
    expect(console_indexes.size).to be >= 15, "only #{console_indexes.size} console index routes found"
  end

  console_indexes.each do |resource|
    it "opens #{resource[:path]}" do
      get resource[:path]

      expect(response).to have_http_status(:ok),
                          "#{resource[:path]} answered #{response.status} — an operator clicking this " \
                          "gets nothing, and no other spec fetches it"
    end

    # ── AND WITH EVERY FILTER APPLIED ────────────────────────────────────
    #
    # The filters are where two of the three failure modes live, and
    # `every_console_filter_runs_spec` calls the lambdas in isolation. This is
    # the other half: through the real request, where a filter that raises
    # becomes the operator's 500.
    it "opens #{resource[:path]} with each of its filters" do
      dashboard = "#{resource[:controller].sub('admin/', '').classify}Dashboard".safe_constantize
      filters = dashboard&.const_defined?(:COLLECTION_FILTERS) ? dashboard::COLLECTION_FILTERS.keys : []
      next if filters.empty?

      filters.each do |name|
        get resource[:path], params: { search: "#{name}:" }

        expect(response).to have_http_status(:ok),
                            "#{resource[:path]} with filter `#{name}` answered #{response.status}"
      end
    end
  end
end
