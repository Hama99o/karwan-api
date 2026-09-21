require "rails_helper"

# ═══ A CONFIG ROW THAT CHANGES NOTHING IS WORSE THAN A MISSING ONE ═════════
#
# Correction 13 is the promise: commission, fees, limits and speeds are
# `Setting` rows so Hamma9900 "retunes prices from the admin console with no
# deploy". A row no code reads breaks that promise in the most expensive way
# available — he types a number, the screen accepts it, and nothing happens.
# `Setting`'s own file says so about the price keys it had deleted: *"a dead
# price key on the Config screen is a number Hamma9900 would type and watch do
# nothing."*
#
# It found `commission_rate` — named after the most important number in the
# business — read by nothing at all, because `merchants.commission_rate` is
# `null: false` with a DATABASE default and a new shop took its rate from the
# schema. It is now the standard rate a new shop onboards at.
#
# ── WHAT THIS GATE GOT WRONG FIRST, WHICH IS WHY IT LOOKS LIKE THIS ───────
#
# Written first as "does the key appear in app/", it passed for every key —
# **because `Setting::DEFINITIONS` is itself in `app/`**. The definition was
# being read as a use, so the assertion could not fail. It reported zero dead
# rows at the moment there were two.
#
# The second version tried to be clever about dynamically-built keys by
# accepting any prefix that appeared in the source. That swallowed the check
# from the other end: `delivery_base_fee_on_tuesdays` passed because
# `delivery_base_fee` is read. Both failures are the same one — a matcher
# widened until nothing could fail it.
#
# So there is no cleverness here. A key is read if its literal appears outside
# `setting.rb`, or it is NAMED in one of two lists below with a reason, and each
# dynamic entry names the file and the fragment that builds it — **which this
# spec then checks is really there**. Same shape as `NOT_MONEY` in the currency
# gate and `ACCOUNTED_FOR` in the error-code gate, both of which work.
RSpec.describe "every Setting row is read by something" do
  # Keys assembled at runtime, so no literal exists to find. Each names the file
  # that builds it and a fragment of the construction, asserted below — an
  # excuse that cannot be checked is just a list of keys somebody wanted green.
  # `let`, NOT a constant. A constant in a describe block lands on `Object`, and
  # two gates in this suite once collided that way — one leaked an Array and the
  # other a String under the same name, the String won, and `include?` quietly
  # became a substring test. Green alone, wrong in the full run.
  let(:built_dynamically) do
    {
    %w[dispatch_max_offer_radius_km_motorbike dispatch_max_offer_radius_km_bicycle
       dispatch_max_offer_radius_km_car dispatch_max_offer_radius_km_on_foot
       dispatch_max_offer_radius_km_rishka dispatch_max_offer_radius_km_zarang] => {
         file: "app/services/dispatch/offer_radius.rb",
         fragment: '"#{GLOBAL_KEY}_#{vehicle_type}"'
       },
    %w[password_reset_email_subject_ps password_reset_email_subject_fa
       password_reset_email_body_ps password_reset_email_body_fa] => {
         file: "app/mailers/user_mailer.rb",
         fragment: '"password_reset_email_body_#{suffix(locale)}"'
       }
    }
  end

  # Deliberately not wired, with the reason. A key may sit here; it may not sit
  # here silently.
  #
  # `batch_max_jobs` is correction 19's: multi-job is "the most important thing"
  # and explicitly NOT in v0, because it needs concurrent demand one
  # neighbourhood will not have on launch day. The guard that will read it is
  # `Dispatch::Eligibility#carrying_another_job?`, which today refuses any second
  # job unconditionally. The row stays so the shape is not forgotten; this entry
  # is what stops it being mistaken for a working control — its description
  # invites raising it to 3, and doing so today does nothing.
  let(:not_wired_yet) do
    {
      "batch_max_jobs" => "correction 19 — batching is not in v0; Dispatch::Eligibility refuses any second job"
    }
  end

  # EXCLUDING `setting.rb`, which is where the definitions live. Including it is
  # what made the first version of this spec unable to fail.
  let(:app_source) do
    Dir[Rails.root.join("app/**/*.rb"), Rails.root.join("lib/**/*.rb")]
      .reject { |file| file.end_with?("app/models/setting.rb") }
      .map { |file| File.read(file) }.join("\n")
  end

  let(:declared) { built_dynamically.keys.flatten + not_wired_yet.keys }

  it "has no row that nothing reads" do
    dead = Setting::DEFINITIONS.keys.reject { |key| app_source.include?(%("#{key}")) } - declared

    expect(dead).to be_empty,
                    "these rows appear on the Config screen and nothing in app/ or lib/ reads them: " \
                    "#{dead.join(', ')}. Wire it, delete it, or name it above with the reason — a number " \
                    "Hamma9900 can type that does nothing is the worst row on that screen."
  end

  # THE EXCUSES ARE CHECKED, NOT TRUSTED. If the builder is renamed or the
  # construction changes shape, the list stops describing the code and this says
  # so rather than going on vouching for it.
  it "proves every dynamic key really is built where it claims" do
    built_dynamically.each_value do |source|
      path = Rails.root.join(source[:file])
      expect(path).to exist, "#{source[:file]} is named as a key builder and does not exist"
      expect(path.read).to include(source[:fragment]),
                           "#{source[:file]} no longer contains #{source[:fragment]} — the keys it vouches for " \
                           "may now be read by nothing"
    end
  end

  # So the lists cannot rot into a place keys go to be forgotten.
  it "keeps no stale excuse for a key that is now read outright" do
    stale = declared.select { |key| app_source.include?(%("#{key}")) }

    expect(stale).to be_empty, "#{stale.join(', ')} is excused and is now read literally. Remove the excuse."
  end

  it "excuses no key that has stopped existing" do
    expect(declared - Setting::DEFINITIONS.keys).to be_empty
    expect(not_wired_yet.values).to all(be_present)
  end

  # ── THE GATE CAN GO RED, PROVEN HERE ─────────────────────────────────────
  #
  # The first two versions of this spec could not, in opposite ways. This runs
  # the real rule against a source that is missing a key it must catch, and
  # against one that contains it.
  it "reports a key whose literal is absent and passes one whose literal is there" do
    rule = ->(key, source) { source.include?(%("#{key}")) }

    expect(rule.call("delivery_base_fee", %(Setting.fetch("delivery_base_fee")))).to be(true)
    expect(rule.call("delivery_base_fee_on_tuesdays", %(Setting.fetch("delivery_base_fee")))).to be(false),
                                                                                              "a longer key is " \
                                                                                              "passing on a shorter " \
                                                                                              "key's literal"
    expect(rule.call("commission_rate", "")).to be(false)
  end
end
