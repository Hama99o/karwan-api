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

  # ── THE CMD OF THE STAGE THAT SHIPS, NOT THE FIRST ONE IN THE FILE ───────
  #
  # This used to take `dockerfile[/^CMD …/]` — the first CMD in the file — which
  # was exact while the Dockerfile had one stage with one CMD. On 2026-09-19 a
  # `development` stage was added ABOVE the final stage, and its CMD is
  # `["./bin/rails", "server", "-b", "0.0.0.0", "-p", "3017"]`. The spec began
  # reading that one and failed, reporting that a deploy would skip migrations.
  #
  # **The deploy was fine and the instrument was wrong**, but only by luck of
  # which direction it erred: the same silent re-aim would have PASSED if the
  # new stage's CMD had happened to end in `./bin/rails server`, while the
  # shipping CMD broke underneath it.
  #
  # The pairing that actually matters is ENTRYPOINT and CMD **in the same
  # stage** — the condition can only fire where the entrypoint runs. The
  # development stage inherits no ENTRYPOINT (`base` has none), so its CMD runs
  # directly and must NOT be judged by this rule; it also must not migrate,
  # which is deliberate: `docker compose up` should never apply a migration.
  def shipping_stage
    stages = dockerfile.split(/^FROM /).drop(1)
    with_entrypoint = stages.select { |stage| stage =~ /^ENTRYPOINT\s*\[/ }

    expect(with_entrypoint.size).to eq(1),
                                    "#{with_entrypoint.size} stages declare an ENTRYPOINT. This spec assumes " \
                                    "exactly one ships; say which, or it will judge the wrong CMD."
    with_entrypoint.first
  end

  # `CMD ["a", "b", "c"]` → ["a", "b", "c"]
  def cmd_args
    raw = shipping_stage[/^CMD\s*\[(.+)\]\s*$/, 1]
    raise "the stage that carries the ENTRYPOINT has no exec-form CMD" if raw.nil?

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

  # Makes the multi-stage assumption visible rather than implied. If a second
  # shipping stage is ever added, this says so in one line instead of the gate
  # quietly judging whichever CMD it met first.
  it "judges the CMD that belongs to the ENTRYPOINT, not the first in the file" do
    all_cmds = dockerfile.scan(/^CMD\s*\[(.+)\]\s*$/).flatten

    expect(all_cmds.size).to be >= 1
    expect(cmd_args).to eq(%w[./bin/thrust ./bin/rails server]),
                        "the shipping CMD changed. If that was deliberate, check it still ends in " \
                        "`./bin/rails server` or the entrypoint will skip db:prepare."
    expect(shipping_stage).not_to include("-p", "3017"),
                                  "the development stage is being read as the shipping one"
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
