require "rails_helper"

# ── THE PUBLISHED SURFACE MUST BE THE REAL ONE ─────────────────────────────
#
# `docs/API_SURFACE.txt` exists so the mobile repo can diff its client list
# against what this API actually serves. Neither side can see the other: this
# one knows what it SERVES and not who calls it, that one knows what it CALLS
# and not what exists. `GET /api/v1/courier/wallet/settlements` was complete —
# route, serializer, request specs — and had no client for as long as it did
# because nobody could ask that question.
#
# A STALE PUBLISHED LIST IS WORSE THAN NO LIST. A diff against a list that is
# three endpoints out of date reports three findings that are not true, and the
# person reading it has no way to tell. So the snapshot is not documentation
# that someone remembers to refresh; it is asserted here and breaks the build.
RSpec.describe "docs/API_SURFACE.txt" do
  def live_surface
    Rails.application.routes.routes.filter_map do |route|
      path = route.path.spec.to_s.sub(/\(\.:format\)\z/, "")
      next unless path.start_with?("/api/")

      verb = route.verb.presence || "ANY"
      format("%-6s %-52s %s", verb, path, "#{route.defaults[:controller]}##{route.defaults[:action]}")
    end.uniq.sort
  end

  it "lists exactly the endpoints this API serves" do
    committed = Rails.root.join("docs/API_SURFACE.txt").read.lines.map(&:chomp).reject(&:empty?)

    expect(committed).to eq(live_surface),
                         "the API surface changed. Regenerate with `bin/endpoints > docs/API_SURFACE.txt` " \
                         "and tell the mobile session — it diffs its client list against this file."
  end

  # Guards the guard. If the filter ever stopped matching — a namespace rename,
  # a prefix change — `live_surface` would return [] and the comparison above
  # would be an empty list equal to an empty file. That is the vacuous pass this
  # repo keeps finding, so the subject is counted before it is compared.
  it "is not comparing two empty lists" do
    expect(live_surface.size).to be > 40
    expect(live_surface).to include(a_string_matching(%r{GET\s+/api/v1/courier/wallet/settlements}))
  end
end
