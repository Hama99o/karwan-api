require "rails_helper"

# EVERY RATE LIMIT FORGOT EVERYTHING ON EVERY DEPLOY, until 25 Sept 2026.
#
# production.rb set no cache_store, so Rails.cache (and so every throttle)
# was the default FileStore under the container's tmp/cache. One host still
# counted, but tmp/ goes with the container, so each deploy reset the
# sign-in, password-reset, OTP and routing limits; a second container would
# have split every limit N ways. `karwan_production_cache` was declared in
# database.yml the whole time, with no schema and nothing using it.
#
# PROVED ONCE AT THE PRODUCTION LAYER (docs/NOTES.md): 11 hits in one
# process, then a new process with an emptied tmp/cache. solid_cache read 11
# and the refusal stood; the default store, planted back, read 0.
#
# This spec keeps the wiring from coming undone. It reads the three files
# that make it true, because the test environment cannot boot production's
# store.
RSpec.describe "rate limits survive a deploy" do
  def read(path) = Rails.root.join(path).read.lines.reject { _1 =~ /\A\s*#/ }.join

  it "keeps production's cache in solid_cache, not in the container" do
    expect(read("config/environments/production.rb")).to match(/^\s*config\.cache_store = :solid_cache_store$/)
  end

  it "points solid_cache at the cache database production declares" do
    cache = YAML.safe_load(ERB.new(read("config/cache.yml")).result, aliases: true)
    db = YAML.safe_load(ERB.new(read("config/database.yml")).result, aliases: true)

    expect(cache.dig("production", "database")).to eq("cache")
    expect(db.dig("production", "cache", "database")).to eq("karwan_production_cache")
  end

  # db:prepare builds the cache database from this file; without it the
  # database is created EMPTY and the first throttle write raises (and
  # RateLimitable fails open: no limit at all).
  it "gives that database its table" do
    expect(read("db/cache_schema.rb")).to include('create_table "solid_cache_entries"')
  end
end
