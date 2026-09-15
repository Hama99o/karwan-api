require "rails_helper"

# `bin/preflight` must reject a stranger on the port.
#
# It is the script the next device run depends on, and its most important
# assertion is the one that is easiest to lose: that a 200 is not an identity.
# Measured today — the unrelated application on port 3000 answers `/up` with a
# 200, because it is also a Rails app and Rails ships that route. A preflight
# that stopped at "something answered" is what let `qa.sh doctor` report a green
# API against another application (docs/NOTES.md, UI_FINDINGS.md F-13).
#
# This asserts the SHAPE of the check rather than running it, because running it
# needs a live server and a spec must not depend on one. It is deliberately
# narrow: it fails if the identity step is deleted or weakened, which is the
# realistic way this regresses.
RSpec.describe "bin/preflight" do
  let(:script) { Rails.root.join("bin/preflight") }
  let(:source) { script.read }

  it "exists and is executable" do
    expect(script).to exist
    expect(script).to be_executable
  end

  # The step that makes it worth having.
  it "asserts the API's IDENTITY, not merely that something answered" do
    expect(source).to include("public/merchant_categories")
    expect(source).to include('grep -q \'"merchant_categories"\'')
  end

  it "checks the endpoint the rig checks, so the two cannot disagree" do
    probe = Rails.root.join("../karwan-mobile/qa/lib/common.sh")
    skip "the mobile repo is not beside this one" unless probe.exist?

    # `API_PROBE_PATH` in the rig and this script must name the same endpoint.
    # They were different once — Hatiwal's `/categories` against a Karwan
    # server — and it could only ever answer wrongly.
    expect(probe.read).to include("/public/merchant_categories")
  end

  it "defaults to the port the server actually defaults to" do
    expect(source).to include('PORT="${PORT:-3017}"')
  end

  # An unseeded database means every screen correctly shows an empty state, so a
  # device run proves nothing about layout. That is a prerequisite, not a nicety.
  it "refuses to call an unseeded database ready" do
    expect(source).to include("bin/rails db:seed")
    expect(source).to match(/no merchants/)
  end

  it "starts nothing — a QA run may own the server" do
    expect(source).to include("READ-ONLY")
    expect(source).not_to match(/^\s*(bin\/rails s|docker compose up|rails server)/)
  end
end
