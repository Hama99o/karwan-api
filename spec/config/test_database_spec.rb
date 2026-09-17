require "rails_helper"

# ONE TEST DATABASE PER SESSION.
#
# This box runs several Claude sessions against one repo, and two suites
# sharing one test database do not queue politely: `database_cleaner`
# truncates while the other holds a lock and the loser reports
#
#   0 examples, 0 failures, 1 error occurred outside of examples
#
# which is docs/TESTING.md's own lying-instrument shape — a result that is
# neither a pass nor a fail, and that reads as a red if you are looking for
# one. Measured here on 2026-09-17: a deliberately planted bug came back as
# exactly that, and believing it would have "proved" a gate that never ran.
#
# The seam is `TEST_DB_SUFFIX`, and the property that matters is that it
# DEFAULTS TO NOTHING — a lone session and CI must behave exactly as they did
# before, or this trades a rare collision for a permanent divergence.
RSpec.describe "the test database" do
  let(:source) { Rails.root.join("config/database.yml").read }

  it "names the suffix in the test entry, and only there" do
    test_block = source[/^test:.*?(?=^production:)/m]

    expect(test_block).to include("TEST_DB_SUFFIX")
    expect(source[/^development:.*?(?=^test:)/m]).not_to include("TEST_DB_SUFFIX")
    expect(source[/^production:.*/m]).not_to include("TEST_DB_SUFFIX")
  end

  # The one that must not regress. A default of anything but "" would send a
  # lone session — and CI — to a database nobody has prepared.
  it "defaults to the plain name, so nothing changes for one session or for CI" do
    expect(source).to include(%q{ENV.fetch('TEST_DB_SUFFIX', '')})
  end

  # Proves the suffix reaches the connection rather than merely appearing in
  # the file: this example is running on whatever it resolved to.
  it "is the database this very example is connected to" do
    expected = "karwan_test#{ENV.fetch('TEST_DB_SUFFIX', '')}"

    expect(ActiveRecord::Base.connection_db_config.database).to eq(expected)
  end

  # The derived-not-declared rule this file inherits: `DATABASE_URL` outranks a
  # `database:` key, so a plain key here would run the suite against — and wipe
  # — the DEVELOPMENT database. The suffix must not be the thing that quietly
  # reintroduces that.
  it "still derives the URL rather than declaring a database name" do
    test_block = source[/^test:.*?(?=^production:)/m]

    expect(test_block).to include("url:")
    expect(test_block).not_to match(/^\s+database:/)
  end

  # ── THE LOCK IS ACTUALLY HELD, not merely written ───────────────────────
  #
  # Asserted from INSIDE a running example, by asking Postgres — so it proves
  # the guard is in force for this very process rather than that the source
  # contains the right words. Remove `rails_helper`'s lock and this goes red.
  it "holds an advisory lock on this database while the suite runs" do
    held = ActiveRecord::Base.connection.select_value(<<~SQL.squish)
      SELECT count(*) FROM pg_locks
       WHERE locktype = 'advisory' AND objid = #{EXCLUSIVE_DATABASE_LOCK_KEY}
    SQL

    expect(held.to_i).to be >= 1
  end

  it "keys the lock on the database name, so two suffixes never collide" do
    expect(EXCLUSIVE_DATABASE_LOCK_KEY)
      .to eq(Zlib.crc32(ActiveRecord::Base.connection_db_config.database.to_s))
    expect(Zlib.crc32("karwan_test")).not_to eq(Zlib.crc32("karwan_test_99"))
  end

  it "never resolves to the development database, whatever the suffix" do
    expect(ActiveRecord::Base.connection_db_config.database).to start_with("karwan_test")
  end
end
