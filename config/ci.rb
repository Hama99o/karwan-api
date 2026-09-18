# Run using bin/ci

CI.run do
  step "Setup", "bin/setup --skip-server"

  step "Style: Ruby", "bin/rubocop"

  step "Security: Gem audit", "bin/bundler-audit"
  step "Security: Brakeman code analysis", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"

  # ── THE STEPS THAT WERE MISSING, AND THEY ARE WHAT THE NAME PROMISES ─────
  #
  # `bin/ci` ran setup, style and two security scans and **not one spec**, while
  # `.github/workflows/ci.yml` — the gate that actually protects `main` — runs
  # `zeitwerk:check` and the full suite. So the local command called CI went
  # green on a branch the real CI would reject, and anybody running it before
  # committing had run no test at all.
  #
  # Found 2026-09-18 by re-reading our own exclusions, after the mobile session
  # found a `tsconfig` excluding the very files that carried its 24 type errors.
  # Same shape from the other end: not a gate told to skip a file, but a gate
  # that never named the thing it exists to check. **Two configs, and each was
  # measuring something the other was not.**
  #
  # `zeitwerk:check` is here for the reason the workflow gives: this codebase
  # uses `class_name: Model.name`, which evaluates constants at class-definition
  # time, so an autoload mistake is a boot failure rather than a style one.
  step "Autoloading", "bin/rails zeitwerk:check"
  step "Tests", "bundle exec rspec --format progress"


  # Optional: set a green GitHub commit status to unblock PR merge.
  # Requires the `gh` CLI and `gh extension install basecamp/gh-signoff`.
  # if success?
  #   step "Signoff: All systems go. Ready for merge and deploy.", "gh signoff"
  # else
  #   failure "Signoff: CI failed. Do not merge or deploy.", "Fix the issues and try again."
  # end
end
