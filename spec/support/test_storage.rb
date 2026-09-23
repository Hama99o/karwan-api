# ═══ THE SUITE LEFT EVERY FILE IT EVER ATTACHED, SINCE 15 SEPTEMBER ════════
#
# `config/storage.yml` points the **test** Disk service at `tmp/storage`, and
# nothing ever emptied it. Every `attach` in every example — avatars, merchant
# storefronts, dish photos — and every VARIANT processed from one, wrote a blob
# that outlived the run. Transactional examples roll the ROWS back; the files on
# disk are not in the transaction and never were.
#
# MEASURED on 2026-09-23, before clearing:
#
#   71,088 files   6.46 GB   oldest 15 Sept, newest written by the run 20 minutes earlier
#     46,651 under 1 KB      the metadata and the tiny fixtures
#      3,794 over 1 MB       ← the volume: original images and their variants
#
# It was 7.0 GB of a machine with 11 GB free, on the box this project is built
# on. Not a slow leak: a straight-line one, growing with every suite anybody
# ran.
#
# ── WHY IT SURVIVED THIS LONG ─────────────────────────────────────────────
#
# `bin/rails tmp:clear` does NOT touch `tmp/storage` — it clears cache, sockets
# and screenshots, and Active Storage's disk root is not on its list. So the one
# command whose name promises exactly this did not do it, and `.gitignore`
# hiding the directory meant it never appeared in a `git status` either. Two
# things that would normally surface a problem both, correctly, said nothing.
#
# ── WHAT THIS DOES, AND WHAT IT DELIBERATELY DOES NOT ─────────────────────
#
# After the suite, empty the test service's root. NOT after each example: a
# per-example purge would cost a directory walk 2,700 times and would fight
# parallel runs, and the files are harmless until they accumulate.
#
# It reads the root from the SERVICE rather than hardcoding `tmp/storage`, so
# moving the service in `config/storage.yml` moves the cleanup with it. And it
# refuses to delete anything that is not under `tmp/` — a guard against the day
# somebody points the test service at `storage/`, which holds real seeded
# images, and this quietly deletes them.
module TestStorage
  KEEP = ".keep".freeze

  def self.root
    service = ActiveStorage::Blob.service
    service.respond_to?(:root) ? Pathname.new(service.root) : nil
  end

  # True only for a path inside this repo's `tmp/`. Anything else is somebody's
  # real data and this never touches it.
  def self.disposable?(path)
    return false if path.nil?

    path.to_s.start_with?(Rails.root.join("tmp").to_s)
  end

  def self.purge!
    directory = root
    return :not_a_disk_service if directory.nil?
    return :refused_outside_tmp unless disposable?(directory)
    return :nothing_there unless directory.exist?

    directory.children.each { |child| FileUtils.rm_rf(child) unless child.basename.to_s == KEEP }
    :purged
  end
end

RSpec.configure do |config|
  # Only the full run tidies up. A single-file run during development leaves its
  # handful of blobs, which is worth nothing to clear and is occasionally worth
  # inspecting.
  config.after(:suite) { TestStorage.purge! }
end
