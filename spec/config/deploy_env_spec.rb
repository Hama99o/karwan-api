require "rails_helper"

# ═══ EVERY ENV KEY THE APP READS MUST HAVE SOMEWHERE TO COME FROM ══════════
#
# Hamma9900's instruction was *"deployment copied from Hatiwal, config complete
# without an IP"*. A config that is shaped and waiting is complete; one that
# silently omits credentials the app reads is not — it is a container that
# boots with a nil and fails somewhere nobody predicted.
#
# That is exactly what had happened. The app read five `SMTP_*` keys and
# `SMS_PROVIDER` — **the two gateways correction 14 names as the only permitted
# third-party dependencies** — and `config/deploy.yml` had nowhere to put any of
# them. `bin/preflight` refuses to pass a deployed box without `SMTP_ADDRESS`,
# so the two halves did not meet: one demanded a value the other could not
# supply.
#
# ── WHY THE LIST IS SCANNED AND NOT TYPED ────────────────────────────────
#
# Key 34 will be added by somebody who forgets, exactly as keys 1–33 were. A
# hand-written list is a denominator that drifts and never says so — the same
# reason `ROUTED` in the admin audit gate is asked of the router. So this reads
# the source.
RSpec.describe "deploy configuration covers every ENV key" do
  SCANNED = %w[app/**/*.rb config/**/*.rb config/*.yml lib/**/*.rb db/**/*.rb].freeze

  # Kamal's OWN variables, consumed by `deploy.yml` before the app exists.
  # `KAMAL_HOST` having no default IS the "complete without an IP" design: the
  # server is supplied at deploy time, which is why `kamal config` refuses
  # without it rather than inventing one.
  KAMAL_OWN = %w[KAMAL_HOST KAMAL_PROXY_HOST KAMAL_IMAGE KAMAL_REGISTRY_USERNAME
                 SSH_USER SSH_KEY_PATH].freeze

  # Read by the RUNTIME rather than by us — Bundler, Puma and CI set these
  # themselves, and a nil is the documented "not set" for each. Listed by name
  # rather than by pattern so a new one has to be justified here.
  RUNTIME_OWN = %w[BUNDLE_GEMFILE CI PIDFILE WEB_CONCURRENCY].freeze

  def source
    @source ||= SCANNED.flat_map { |glob| Rails.root.glob(glob) }
                       .reject { |path| path.to_s.include?("/spec/") }
                       .map(&:read).join("\n")
  end

  # `ENV.fetch("X", default)` and `ENV.fetch("X") { default }` carry their own
  # fallback. `ENV["X"]` and a bare `ENV.fetch("X")` do not.
  def keys_with_defaults
    source.scan(/ENV\.fetch\(\s*"([A-Z_0-9]+)"\s*,/).flatten.uniq +
      source.scan(/ENV\.fetch\(\s*"([A-Z_0-9]+)"\s*\)\s*\{/).flatten.uniq
  end

  def keys_without_defaults
    (source.scan(/ENV\[\s*"([A-Z_0-9]+)"\s*\]/).flatten +
      source.scan(/ENV\.fetch\(\s*"([A-Z_0-9]+)"\s*\)(?!\s*\{)/).flatten).uniq
  end

  def declared
    deploy = Rails.root.join("config/deploy.yml").read
    secrets = Rails.root.join(".kamal/secrets").read

    (deploy.scan(/^\s+-\s*([A-Z_0-9]+)\s*$/).flatten +
      deploy.scan(/^\s+([A-Z_0-9]+):/).flatten +
      secrets.scan(/^([A-Z_0-9]+)=/).flatten).uniq
  end

  it "reads a plausible number of keys, so a broken scan cannot pass quietly" do
    all = (keys_with_defaults + keys_without_defaults).uniq

    expect(all.size).to be >= 30, "the scan found #{all.size} keys — it is probably broken"
    expect(all).to include("DATABASE_URL", "SMTP_ADDRESS", "SMS_PROVIDER")
  end

  # ── THE GATE ─────────────────────────────────────────────────────────────
  #
  # A key with no default and no declaration is a nil in production, arriving
  # wherever it is first used.
  it "leaves no key undeclared without a default" do
    orphans = keys_without_defaults - keys_with_defaults - declared - KAMAL_OWN - RUNTIME_OWN

    expect(orphans).to be_empty,
                       "these are read with no default and declared nowhere: #{orphans.sort.join(', ')}"
  end

  # The two gateways specifically, because they are the ones that were missing
  # and the ones correction 14 permits at all.
  it "gives both gateways a slot in deploy.yml and in secrets" do
    deploy = Rails.root.join("config/deploy.yml").read
    secrets = Rails.root.join(".kamal/secrets").read

    %w[SMTP_ADDRESS SMTP_USER_NAME SMTP_PASSWORD SMS_PROVIDER].each do |key|
      expect(deploy).to match(/^\s+-\s*#{key}\s*$/), "#{key} has no slot in deploy.yml"
      expect(secrets).to match(/^#{key}=/), "#{key} has no line in .kamal/secrets"
    end
  end

  # NAMES AND COMMENTS, NEVER VALUES. An invented host or a plausible-looking
  # placeholder is worse than a blank: it boots, it reads as configured, and the
  # failure lands somewhere nobody predicted. The honest shape is a named slot
  # plus preflight's refusal to start without it.
  it "commits no credential, only the shape of one" do
    secrets = Rails.root.join(".kamal/secrets").read

    secrets.each_line do |line|
      next unless line =~ /^[A-Z_0-9]+=/

      value = line.split("=", 2).last.to_s.strip
      expect(value).to match(/\A\$\(/),
                       "#{line.split('=').first} looks like a literal value, not a lookup"
    end
  end

  # preflight demands `SMTP_ADDRESS` on a deployed box. If the slot for it ever
  # disappears, the deploy can never satisfy the check — the two halves must
  # stay in step.
  it "can supply what bin/preflight refuses to deploy without" do
    preflight = Rails.root.join("bin/preflight").read

    expect(preflight).to include("SMTP_ADDRESS")
    expect(declared).to include("SMTP_ADDRESS")
  end
end
