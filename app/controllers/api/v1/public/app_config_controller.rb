# The handful of settings the APP needs, before anyone logs in.
#
# ── Why this exists ───────────────────────────────────────────────────────
# `support_phone` is already a `Setting` row — correction 13 makes every such
# number admin-tunable with no deploy — and it was reachable from exactly one
# place: inside a COURIER's wallet payload. So a customer could not see it, a
# merchant could not see it, and a first-time user who has not logged in
# certainly could not.
#
# AFGHAN_UX.md §1 asks for that number on every screen of every role, and calls
# it "the fallback that always works" — the thing someone reaches for when the
# interface has already failed them. A value only a signed-in courier can read
# cannot be that.
#
# The mobile app held it as a build-time constant instead, which meant changing
# it was a REBUILD. Now Hamma9900 types it into the admin console and every
# installed app picks it up.
#
# ── An ALLOWLIST, never the Setting table ─────────────────────────────────
# Most settings are the business's own numbers — commission rates, credit
# lines, cash limits, dispatch parameters. None of that is a customer's
# business and some of it would tell a courier exactly how much we make on
# them. So this serves named keys and nothing else, and adding one is a
# deliberate act with a reason.
class Api::V1::Public::AppConfigController < Api::V1::PublicController
  # What a CLIENT may know. Each entry needs a reason to be here.
  PUBLIC_SETTINGS = {
    # The number on every screen, in every role, for a user who cannot read
    # the interface.
    support_phone: "support_phone"
  }.freeze

  def show
    skip_authorization

    render_ok({
      app_config: PUBLIC_SETTINGS.transform_values { |key| Setting.fetch(key) }
    })
  end
end
