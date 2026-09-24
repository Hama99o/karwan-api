require "rails_helper"

# ═══ THE FILE THAT MAKES TIMEOUTS EXIST WAS GUARDED BY NOTHING ═════════════
#
# `config/recurring.yml`'s own header: *"These are what make dispatch and
# timeouts EXIST — the offer deadline and the state timeouts were declared in
# the models long before anything ran them, which made the whole mechanism look
# implemented while nothing enforced it."*
#
# That is a description of a defect this repo already had, and the file that
# fixed it had no spec. A renamed job, a typo in a class name, or a new sweep
# added without a schedule entry puts it straight back — and silently, because
# a sweep that never runs raises nothing. The orders simply sit.
RSpec.describe "config/recurring.yml" do
  let(:schedule) { YAML.load_file(Rails.root.join("config/recurring.yml"), aliases: true) }
  let(:production) { schedule.fetch("production") }

  # Sweeps: nothing in a request triggers them, so the schedule is the ONLY
  # thing that runs them. A notification job is the opposite — it is enqueued by
  # the event that needs it and must not be on a timer.
  let(:sweep_jobs) do
    Dir[Rails.root.join("app/jobs/dispatch/*_job.rb")].map { |f| File.basename(f, ".rb").camelize }
                                                      .map { |name| "Dispatch::#{name}" }
  end

  # ── EVERY JOB RUNS SOMEHOW, WHEREVER IT LIVES ─────────────────────────
  #
  # Audited 2026-09-24: `sweep_jobs` is the dispatch folder, so the check that
  # every sweep has a schedule could not see one anywhere else — and
  # `Merchants::IssueWeeklyStatementsJob` already lives elsewhere; it is on the
  # schedule today only because somebody remembered. From the other side:
  # every job class must be either enqueued by something in app/ or on the
  # schedule. A job with neither is code that never runs.
  it "leaves no job that nothing enqueues and nothing schedules" do
    scheduled = production.values.map { |task| task["class"] }
    app_source = Dir[Rails.root.join("app/**/*.rb")].map { |f| File.read(f) }.join("\n")
    jobs = Dir[Rails.root.join("app/jobs/**/*_job.rb")].map { |f| f.sub(%r{.*/app/jobs/}, "").delete_suffix(".rb").camelize }
                                                        .reject { |name| name == "ApplicationJob" }

    orphans = jobs.reject do |job|
      scheduled.include?(job) || app_source.match?(/\b#{Regexp.escape(job.demodulize)}\.(?:perform_later|perform_now|set)\b/)
    end

    expect(jobs.size).to be >= 5
    expect(orphans).to be_empty, "these jobs are neither enqueued anywhere nor scheduled, so they never run: #{orphans.join(', ')}"
  end

  it "finds the schedule and the sweeps at all" do
    expect(production).to be_present
    expect(sweep_jobs.size).to be >= 3, "no sweep jobs found — every check below is vacuous"
  end

  # A class named here that does not exist is a task that never runs. Solid
  # Queue resolves it at dispatch time, so the failure is a log line on a
  # server, months later, about an order nobody is watching.
  it "names only classes that exist and are jobs" do
    broken = production.filter_map do |name, task|
      klass = task["class"]
      next if klass.blank?

      resolved = klass.safe_constantize
      "#{name}: #{klass} #{resolved.nil? ? 'does not exist' : 'is not an ActiveJob'}" unless
        resolved&.ancestors&.include?(ActiveJob::Base)
    end

    expect(broken).to be_empty, broken.join("\n")
  end

  # THE FAILURE THE HEADER DESCRIBES. A sweep exists in app/jobs and nothing
  # runs it — the mechanism looks implemented and enforces nothing.
  it "schedules every dispatch sweep" do
    scheduled = production.values.filter_map { |task| task["class"] }

    expect(sweep_jobs - scheduled).to be_empty,
                                      "these sweeps exist and nothing runs them: #{(sweep_jobs - scheduled).join(', ')}. " \
                                      "A sweep with no schedule raises nothing — the orders just sit."
  end

  # ── AND DEVELOPMENT RUNS THEM TOO ────────────────────────────────────────
  #
  # Not tidiness. A developer whose timeouts never fire builds against a system
  # where orders never time out, and every screen is tested in a state
  # production will not produce. The file uses a YAML anchor so the two cannot
  # drift; this asserts the anchor is actually applied.
  it "gives development the same tasks as production" do
    expect(schedule.fetch("development")).to eq(production)
  end

  # Each task needs a cadence, and one tighter than what it guards. The offer
  # TTL is the tightest thing here, so a sweep slower than it makes the deadline
  # a fiction — the file says so in as many words.
  it "gives every task a schedule" do
    unscheduled = production.reject { |_name, task| task["schedule"].present? }.keys

    expect(unscheduled).to be_empty, "no cadence for: #{unscheduled.join(', ')}"
  end

  it "sweeps for expired offers more often than the offer lives" do
    ttl = Setting.fetch("dispatch_offer_ttl_sec").to_i
    cadence = production.dig("expire_dispatch_offers", "schedule")

    expect(cadence).to match(/every (\d+) seconds/)
    expect(cadence[/\d+/].to_i).to be < ttl,
                                   "the sweep runs every #{cadence[/\d+/]}s against a #{ttl}s TTL, so the " \
                                   "deadline a courier is promised is longer than the one enforced"
  end
end
