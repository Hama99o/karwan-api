require "rails_helper"

# ═══ THE GATE CALLED "CI" RAN NO TESTS ═════════════════════════════════════
#
# `config/ci.rb` ran setup, style and two security scans and **not one spec**,
# while `.github/workflows/ci.yml` — the gate that actually protects `main` —
# runs `zeitwerk:check` and the full suite. So `bin/ci` went green on a branch
# the real CI would reject, and anybody running it before committing had run no
# test at all.
#
# Found 2026-09-18 by re-reading our own exclusions after the mobile session
# found a `tsconfig` excluding the very files carrying its 24 type errors. Same
# shape from the other end: not a gate told to skip a file, but **a gate that
# never named the thing it exists to check**.
#
# ── WHY THIS IS ASSERTED AND NOT JUST FIXED ──────────────────────────────
#
# The two configs drifted once and nothing said so. Anyone can add a step to the
# workflow and not to `bin/ci`, or the reverse, and the next person to trust the
# shorter one gets a false green. This compares them to each other, so the
# divergence is what fails rather than the consequence of it.
RSpec.describe "bin/ci and the workflow agree" do
  let(:local) { Rails.root.join("config/ci.rb").read }
  let(:workflow_path) { Rails.root.join(".github/workflows/ci.yml") }
  let(:workflow) { workflow_path.read }

  it "has a workflow to compare against, or everything below is vacuous" do
    expect(workflow_path).to exist
    expect(workflow).to include("rspec")
  end

  it "runs the suite locally, because a gate named CI that runs no test is a lie" do
    expect(local).to match(/step "Tests".*rspec/),
                     "bin/ci does not run the suite — it can be green on a branch the real CI rejects"
  end

  # `class_name: Model.name` evaluates constants at class-definition time, so an
  # autoload mistake here is a boot failure rather than a style one. The
  # workflow checks it; the local gate did not.
  it "checks autoloading locally too" do
    expect(local).to include("zeitwerk:check")
  end

  # The anti-drift pair. Each command the WORKFLOW gates `main` with should be
  # reachable from `bin/ci`, so somebody running the short one is not running a
  # different product.
  it "omits nothing the workflow gates main with" do
    gated = {
      "rubocop" => "bin/rubocop",
      "bundler-audit" => "bin/bundler-audit",
      "brakeman" => "bin/brakeman",
      "zeitwerk:check" => "zeitwerk:check",
      "rspec" => "rspec"
    }

    missing = gated.select { |_name, fragment| workflow.include?(fragment) && !local.include?(fragment) }

    expect(missing.keys).to be_empty,
                            "the workflow gates main with these and bin/ci does not run them: #{missing.keys.join(', ')}"
  end
end
