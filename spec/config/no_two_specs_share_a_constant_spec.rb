require "rails_helper"

# ═══ A CONSTANT IN A DESCRIBE BLOCK LANDS ON `Object` ══════════════════════
#
# RSpec runs a `describe` body in a class, but a constant assigned there is not
# scoped to it — it is defined on `Object` and visible to every other spec in
# the run. Two files using the same name silently share one value, and the
# winner is whichever loaded last.
#
# **The failure looks like a bug in the innocent file.** Defining `RESOURCES`
# here as an array of Hashes broke `dashboards_spec.rb`, which had its own
# `RESOURCES` of strings, with *"comparison of Hash with Hash failed"* — in a
# file nothing had touched. It passes when either file is run alone and fails
# in the full suite, which is the worst debugging shape available.
#
# ── WHY THIS AND NOT "DO NOT USE CONSTANTS IN SPECS" ─────────────────────
#
# Forty-one of them exist here and almost all are fine: a name used once is a
# constant on `Object` that nothing else reads. **The defect is the COLLISION,
# not the practice**, so this asserts the thing that actually breaks rather than
# the habit that usually does not — a gate that flagged all forty-one would be
# switched off by the second week.
#
# `docs/TESTING.md` already records this shape from two earlier gates that
# leaked `SANCTIONED` and turned an `include?` into a substring test. Three
# occurrences, and the repo's own rule is to extract on the third.
RSpec.describe "no two spec files declare the same constant" do
  # Indented, so nested inside a block rather than at file scope. `==` excluded
  # so a comparison is not read as an assignment.
  DECLARATION = /^[ \t]{2,}([A-Z][A-Z0-9_]+)[ \t]*=[^=]/

  # Names that are deliberately shared, each with the reason.
  let(:shared_on_purpose) do
    {
      "TEST_DB_SUFFIX" => "the env var's own name, quoted in rails_helper's guidance text rather than assigned"
    }
  end

  let(:declarations) do
    Dir[Rails.root.join("spec/**/*_spec.rb")].each_with_object(Hash.new { |h, k| h[k] = [] }) do |file, found|
      File.readlines(file).each do |line|
        name = line[DECLARATION, 1]
        found[name] << file.sub("#{Rails.root}/", "") if name
      end
    end
  end

  it "finds declarations at all, or this asserts nothing" do
    expect(declarations.size).to be >= 15, "only #{declarations.size} constants found in specs"
  end

  it "declares no name in two different files" do
    collisions = declarations.reject { |name, _| shared_on_purpose.key?(name) }
                             .select { |_name, files| files.uniq.size > 1 }

    expect(collisions).to be_empty,
                          collisions.map { |name, files|
                            "#{name} is declared in #{files.uniq.join(' and ')} — both land on Object, the last " \
                            "one loaded wins, and the failure appears in whichever file did NOT change"
                          }.join("\n")
  end

  it "names a reason for every deliberate sharing" do
    expect(shared_on_purpose.values).to all(be_present)
  end

  # ── THE GATE CAN GO RED ──────────────────────────────────────────────────
  #
  # Run against a source that contains the collision, so this cannot join the
  # checks that pass because the repo happens to be clean today.
  it "reports a name declared twice" do
    sample = { "RESOURCES" => %w[a_spec.rb b_spec.rb], "UNIQUE" => %w[a_spec.rb] }

    expect(sample.select { |_n, f| f.uniq.size > 1 }.keys).to eq(%w[RESOURCES])
    expect("  RESOURCES = [1]"[DECLARATION, 1]).to eq("RESOURCES")
    expect("  expect(A == B)"[DECLARATION, 1]).to be_nil, "a comparison is being read as a declaration"
  end
end
