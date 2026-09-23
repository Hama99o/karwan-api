# `bin/rails tmp:clear` does not touch Active Storage's disk root, and that is
# why `tmp/storage` reached **71,088 files and 6.46 GB** before anybody looked —
# on a machine with 11 GB free. The one command whose name promises to empty
# `tmp` did not empty the largest thing in it, and `.gitignore` kept it out of
# `git status` too, so neither of the two places a person would normally notice
# said anything.
#
# The suite now tidies up after itself (`spec/support/test_storage.rb`). This is
# for the other half: a human, or a deploy script, running the obvious command.
#
# It targets the literal `tmp/storage` rather than the CURRENT environment's
# service on purpose. In development the service is `local`, whose root is
# `storage/` — real seeded images, not disposable — and a task that resolved the
# service at runtime would delete those when run without RAILS_ENV=test.
namespace :tmp do
  desc "Empty Active Storage's test disk root (tmp/storage), which tmp:clear does not"
  task clear_storage: :environment do
    root = Rails.root.join("tmp/storage")
    abort "refusing: #{root} is not under tmp/" unless root.to_s.start_with?(Rails.root.join("tmp").to_s)
    next unless root.exist?

    before = root.children.size
    root.children.each { |child| FileUtils.rm_rf(child) unless child.basename.to_s == ".keep" }
    puts "[tmp:clear_storage] emptied #{root} (#{before} entries)"
  end
end

Rake::Task["tmp:clear"].enhance([ "tmp:clear_storage" ]) if Rake::Task.task_defined?("tmp:clear")
