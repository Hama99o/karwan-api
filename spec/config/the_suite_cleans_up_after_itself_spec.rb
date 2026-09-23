require "rails_helper"

# ═══ 71,088 FILES AND 6.46 GB, FROM A SUITE THAT NEVER SWEPT UP ════════════
#
# `config/storage.yml` points the test Disk service at `tmp/storage`. Every
# `attach` in every example, and every variant processed from one, wrote a blob
# that outlived the run — transactional examples roll the ROWS back, and the
# files were never in the transaction.
#
# Measured on 2026-09-23 before clearing: 71,088 files, 6.46 GB, oldest 15 Sept,
# newest written by the run twenty minutes earlier. 3,794 of them over 1 MB,
# which is where the volume was. On a box with 11 GB free.
#
# ── WHY NOTHING SURFACED IT ───────────────────────────────────────────────
#
# `bin/rails tmp:clear` does not clear Active Storage's disk root, and
# `.gitignore` keeps the directory out of `git status`. **The two places a
# person would normally notice a 7 GB directory both correctly said nothing.**
# That is the shape of it: not a missing check, a gap between two checks that
# each did their own job.
RSpec.describe "the suite cleans up after itself" do
  let(:root) { TestStorage.root }

  it "puts the test service's blobs under tmp, where they are disposable" do
    expect(root).not_to be_nil, "the test service is not a Disk service any more — this spec is about a disk"
    expect(TestStorage).to be_disposable(root),
                           "the test service writes outside tmp/, so nothing here may delete it"
  end

  it "empties the root but keeps .keep" do
    FileUtils.mkdir_p(root.join("ab", "cd"))
    root.join("ab", "cd", "blob").write("x")
    root.join(TestStorage::KEEP).write("") unless root.join(TestStorage::KEEP).exist?

    expect(TestStorage.purge!).to eq(:purged)

    expect(root.children.map { |c| c.basename.to_s }).to eq([ TestStorage::KEEP ]),
                                                         "a run's blobs outlive it, which is how this reached 6.46 GB"
  end

  # ── THE GUARD THAT MATTERS MORE THAN THE CLEANUP ─────────────────────────
  #
  # `storage/` — the `local` service — holds real seeded images and is 147 MB of
  # things somebody meant to keep. If the test service is ever pointed there,
  # this code must refuse rather than delete them.
  it "refuses to delete anything outside tmp" do
    expect(TestStorage).not_to be_disposable(Rails.root.join("storage")),
                               "the local service's root is real data and must never look disposable"
    expect(TestStorage).not_to be_disposable(Pathname.new("/"))
    expect(TestStorage).not_to be_disposable(nil)
  end

  # ── THE WIRING, ASSERTED THE HONEST WEAK WAY ─────────────────────────────
  #
  # RSpec does not expose its registered `:suite` hooks for inspection, and the
  # first version of this example SKIPPED when it could not find them — a check
  # that cannot fail, which is what most of `docs/TESTING.md` is about. Reading
  # the file is a weaker claim honestly made: it cannot prove the hook fires,
  # and it does go red the moment somebody deletes it. Same idiom as
  # `spec/config/port_spec.rb`, which reads `config/puma.rb` for the same
  # reason — the thing being asserted is not askable at runtime.
  #
  # The hook firing WAS verified, once, by running a suite that attaches a file
  # and looking at the directory afterwards. That is a measurement, not a
  # guard, and it belongs in `docs/NOTES.md` rather than here.
  it "is wired to run after the suite, not after each example" do
    support = Rails.root.join("spec/support/test_storage.rb").read

    expect(support).to include("config.after(:suite)"),
                       "nothing sweeps up, and the directory grows with every run again"
    expect(support).not_to include("config.after(:each)"),
                           "per-example would walk the directory 2,700 times and fight parallel runs"
  end

  # `tmp:clear` is the command whose name promises this and does not do it.
  it "hangs the sweep off tmp:clear, where somebody would look for it" do
    task = Rails.root.join("lib/tasks/tmp_storage.rake").read

    expect(task).to include('Rake::Task["tmp:clear"].enhance')
    expect(task).to include("tmp/storage")
    expect(task).to include("refusing"), "a task that deletes needs a branch that refuses"
  end
end
