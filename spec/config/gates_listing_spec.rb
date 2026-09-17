require "rails_helper"
require "open3"

# ═══ `bin/gates` MUST SPEAK FOR EVERY SPEC FILE ════════════════════════════
#
# It exists to answer one question cheaply — **does a gate for this already
# exist?** — because on 2026-09-17 that question had no cheap answer and got
# answered by writing a gate that already existed. `dashboards_spec.rb` had
# covered it since before that day, and had already caught the rename it was
# built for.
#
# **A listing that silently omits a file is worse than no listing**, because it
# answers "no such gate" with authority. So this asserts the tool speaks for
# every spec file in the tree, derived on both sides — the count comes from the
# filesystem, not from a number typed here.
RSpec.describe "bin/gates" do
  let(:script) { Rails.root.join("bin/gates") }

  def run(*args)
    Open3.capture2e(script.to_s, *args, chdir: Rails.root.to_s)
  end

  it "exists and is executable" do
    expect(script).to exist
    expect(script).to be_executable
  end

  it "lists every spec file in the tree, and says how many" do
    on_disk = Rails.root.glob("spec/**/*_spec.rb").size
    output, status = run

    expect(status).to be_success
    expect(output).to include("#{on_disk} spec files")
  end

  # The failure that would make it lie: a file whose `RSpec.describe` it cannot
  # parse is reported as such rather than dropped silently.
  it "names any file it cannot read rather than omitting it" do
    output, = run

    expect(output).not_to include("no RSpec.describe found"),
                          "some spec files have an unreadable describe — the listing cannot speak for them"
  end

  # The line that would have saved the duplicated work, asserted so the tool
  # keeps being able to answer that question.
  it "shows what a file asserts, not just its name" do
    output, = run

    expect(output).to include("dashboards_spec.rb")
    expect(output).to include("Every ops console page renders")
  end

  it "filters by path so a directory can be scanned on its own" do
    output, status = run("pricing")

    expect(status).to be_success
    expect(output).to include("delivery_quote_spec.rb")
    expect(output).not_to include("dashboards_spec.rb")
  end

  it "tells the reader to run it BEFORE writing a gate, which is the whole point" do
    output, = run

    expect(output).to match(/before writing a new gate/i)
  end
end
