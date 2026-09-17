require "rails_helper"

# ═══ SOMEBODY MUST BE ABLE TO OPEN THE OPS CONSOLE ═════════════════════════
#
# Found by booting the production image against an empty database on
# 2026-09-17. The seed ran, 48 settings appeared, and **`admin_users` was 0** —
# `AdminUser` was created in `db/seeds/sample.rb` and `db/seeds/e2e.rb` only,
# and `db/seeds.rb` skips both in production. So a first deploy produced a
# working API serving real endpoints with an ops console **nobody could log
# into**, and `deploy.yml`'s `admin` alias only COUNTS them.
#
# Every gate in the repo was green. Nothing was broken. It was simply unusable
# — which is the same shape as the unstyled console found in the same hour, and
# neither was findable without running the image.
#
# The mechanism is copied from `hatiwal-api/db/seeds.rb:12-28` (correction 15),
# which solves this and which Karwan had not copied.
RSpec.describe "db/seeds/reference.rb — the first admin" do
  # The section is exercised by loading the real file with a stubbed env, so
  # the test drives the shipped code rather than a copy of its logic.
  def run_reference_admin(env:, env_vars: {})
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new(env))
    original = ENV.to_h
    env_vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }

    # `seed_section` is defined by db/seeds.rb; the reference file assumes it.
    Object.send(:define_method, :seed_section) { |_title, &block| block.call }
    load Rails.root.join("db/seeds/reference.rb")
  ensure
    ENV.replace(original)
    Object.send(:remove_method, :seed_section) if Object.method_defined?(:seed_section)
  end

  describe "in production" do
    it "creates an admin from ADMIN_PASSWORD, so the console can be opened" do
      expect { run_reference_admin(env: "production", env_vars: { "ADMIN_PASSWORD" => "a-long-real-password" }) }
        .to change(AdminUser, :count).by(1)

      admin = AdminUser.find_by(email: "ops@karwan.af")
      expect(admin).to be_present
      expect(admin.valid_password?("a-long-real-password")).to be(true)
    end

    it "takes the address from ADMIN_EMAIL when he sets one" do
      run_reference_admin(env: "production",
                          env_vars: { "ADMIN_PASSWORD" => "a-long-real-password",
                                      "ADMIN_EMAIL" => "hammayoun@karwan.af" })

      expect(AdminUser.find_by(email: "hammayoun@karwan.af")).to be_present
    end

    # ── THE REFUSAL, WHICH IS THE POINT ────────────────────────────────────
    #
    # A console seeded with a password anybody can read in this repo is worse
    # than no console. Raising lands during `db:prepare` on first boot, so the
    # deploy fails loudly with the remedy in the message rather than coming up
    # quietly reachable by a stranger.
    it "REFUSES to invent a password rather than shipping a known one" do
      expect { run_reference_admin(env: "production", env_vars: { "ADMIN_PASSWORD" => nil }) }
        .to raise_error(/ADMIN_PASSWORD must be set/)

      expect(AdminUser.count).to eq(0)
    end

    it "says what to do about it, not just that it is wrong" do
      expect { run_reference_admin(env: "production", env_vars: { "ADMIN_PASSWORD" => nil }) }
        .to raise_error(/\.env\.production/)
    end
  end

  # ── AND NOT OUTSIDE PRODUCTION, WHICH PROTECTS THE QA RIG ────────────────
  #
  # `sample.rb` already creates `ops@karwan.af` with the password the rig signs
  # in with, and it loads AFTER this file. Seeding one here would be either
  # redundant or — the day somebody reorders those loads — a silent change to
  # the rig's credentials. The gap is production-shaped; so is the fix.
  describe "outside production" do
    it "creates nothing in development, leaving the rig's account to sample.rb" do
      expect { run_reference_admin(env: "development", env_vars: { "ADMIN_PASSWORD" => nil }) }
        .not_to change(AdminUser, :count)
    end

    it "does not raise without ADMIN_PASSWORD, so a local seed still works" do
      expect { run_reference_admin(env: "development", env_vars: { "ADMIN_PASSWORD" => nil }) }
        .not_to raise_error
    end
  end
end
