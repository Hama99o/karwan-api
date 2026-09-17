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

  # ── THE SECOND GATEWAY ────────────────────────────────────────────────────
  #
  # SMS had a warning and SMTP had none, so the quieter of the two failures was
  # the unwatched one: `UserMailer#password_reset` is `deliver_later`, so an
  # unset host still answers the request 200 and the app still says "check your
  # email". The SMS path at least writes the code somewhere readable.
  #
  # Asserted as SOURCE SHAPE for the same reason as everything else in this
  # file — a spec must not need a live server. **All three branches were run
  # for real** when this landed, which a grep cannot do:
  #   unset, local         → warning, exit 0
  #   unset, APP_BASE_URL  → ✗ and exit 1
  #   SMTP_ADDRESS set     → ✓ and exit 0
  it "checks for a mail host" do
    expect(source).to include("SMTP_ADDRESS")
  end

  # The distinction that makes the check usable: a laptop has no business
  # holding mail credentials, so warning locally is right — but on a box with a
  # real hostname an unset host is a reset that answers 200 and goes nowhere,
  # and `bad` is what makes preflight exit non-zero.
  it "FAILS rather than warns once the box looks deployed" do
    expect(source).to match(/bad "SMTP_ADDRESS is unset on a DEPLOYED box/)
    expect(source).to include('[ -n "${APP_BASE_URL:-}${KAMAL_HOST:-}" ]')
  end

  # ── THE CONFIG SCREEN, which is correction 13's whole premise ────────────
  #
  # `Setting.fetch` falls back to a definition's default when no row exists, so
  # an unseeded database runs perfectly and shows Hamma9900 a Config screen
  # that is merely SHORT — no error, and "he retunes weekly with no deploy"
  # quietly stops being true. `deploy.yml` puts `seed` under `aliases:`, a
  # shortcut somebody types, and hatiwal-api is the same — so this does not
  # fight the practice, it makes FORGETTING visible.
  #
  # All three branches were RUN when this landed, and the check found two real
  # missing rows on this box on its first execution:
  #   all present            → ✓, exit 0
  #   missing, local         → ·, exit 0
  #   missing, APP_BASE_URL  → ✗, exit 1
  it "checks that every setting has a row he can edit" do
    expect(source).to include("Setting::DEFINITIONS.keys - Setting.pluck(:key)")
  end

  it "FAILS rather than warns about missing rows once the box looks deployed" do
    expect(source).to match(/bad "\$MISSING_COUNT setting\(s\) have no row on a DEPLOYED box/)
  end

  it "starts nothing — a QA run may own the server" do
    expect(source).to include("READ-ONLY")
    expect(source).not_to match(/^\s*(bin\/rails s|docker compose up|rails server)/)
  end
end
