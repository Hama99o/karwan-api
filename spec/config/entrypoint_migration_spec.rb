require "rails_helper"
require "shellwords"

# ═══ THE DEPLOY MIGRATES BECAUSE OF A POSITIONAL MATCH ═════════════════════
#
# `bin/docker-entrypoint` runs `db:prepare` only when the LAST TWO arguments
# are exactly `./bin/rails` and `server`:
#
#   if [ "${@: -2:1}" == "./bin/rails" ] && [ "${@: -1:1}" == "server" ]
#
# and the Dockerfile supplies them as `CMD ["./bin/thrust", "./bin/rails",
# "server"]`. Nothing connects the two files. **Reorder or wrap that CMD and
# the condition silently stops matching** — the deploy comes up, serves
# traffic, and skips migrations, which is the same failure this repo spent an
# afternoon on arriving through a different door. It would present as an app
# answering 500s after a schema change, with nothing naming a migration.
#
# ── WHY THIS EXECUTES RATHER THAN GREPS ──────────────────────────────────
#
# A spec that pattern-matched the condition would be asserting a COPY of it,
# and would agree with itself while the real file said something else. So both
# halves are read from disk and the **actual shell condition is run against the
# actual CMD arguments** — if either file changes in a way that breaks the
# pairing, this goes red for the right reason.
RSpec.describe "the entrypoint migrates on a real deploy" do
  let(:dockerfile) { Rails.root.join("Dockerfile").read }
  let(:entrypoint) { Rails.root.join("bin/docker-entrypoint").read }

  # `CMD ["a", "b", "c"]` → ["a", "b", "c"]
  def cmd_args
    raw = dockerfile[/^CMD\s*\[(.+)\]\s*$/, 1]
    raise "no exec-form CMD found in the Dockerfile" if raw.nil?

    raw.scan(/"([^"]*)"/).flatten
  end

  # The `if …; then` line, taken from the file rather than retyped.
  def entrypoint_condition
    entrypoint[/^if\s+(.+?);\s*then\s*$/, 1] or raise "no `if …; then` in bin/docker-entrypoint"
  end

  def condition_fires_for?(args)
    script = "if #{entrypoint_condition}; then echo FIRES; else echo SKIPS; fi"
    out = `bash -c #{Shellwords.escape(script)} -- #{args.map { |a| Shellwords.escape(a) }.join(' ')}`
    out.strip == "FIRES"
  end

  it "has an exec-form CMD to reason about at all" do
    expect(cmd_args).not_to be_empty
    expect(entrypoint_condition).to include("bin/rails")
  end

  # THE GATE. The real condition, the real arguments.
  it "runs db:prepare for the Dockerfile's own CMD" do
    expect(condition_fires_for?(cmd_args)).to be(true),
                                              "CMD #{cmd_args.inspect} does not satisfy `#{entrypoint_condition}` " \
                                              "— a deploy would boot and skip migrations"
  end

  # The negative control: if the condition fired for ANYTHING, the example
  # above would be worthless. A console container must not migrate.
  it "does not run it for a container that is not the server" do
    expect(condition_fires_for?(%w[./bin/rails console])).to be(false)
    expect(condition_fires_for?(%w[bash])).to be(false)
  end

  # Kamal's `migrate` alias and `bin/preflight` both assume the schema is
  # current after a deploy. That assumption rests entirely on the pairing
  # above, so it is worth naming where somebody will read it.
  it "is what makes `kamal migrate` belt-and-braces rather than required" do
    expect(entrypoint).to include("db:prepare")
    expect(Rails.root.join("docs/RUNBOOK.md").read).to include("db:prepare")
  end
end
