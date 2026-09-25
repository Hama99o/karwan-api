require "rails_helper"

# EVERY PRODUCTION DATABASE database.yml DECLARES MUST HAVE SOMETHING TO BUILD IT.
#
# `db:prepare` creates each declared database and loads `db/<name>_schema.rb`
# into it. With no schema file it creates the database EMPTY and says nothing.
# That happened twice here: `karwan_production_cache` (so every rate limit
# lived in the container and reset on deploy; fixed b5ab84b) and
# `karwan_production_cable` (no table for solid_cable; fixed 25 Sept 2026).
#
# Enumerated FROM database.yml, so a fifth database added later is checked
# without anyone remembering to list it here.
RSpec.describe "every declared production database has a schema" do
  let(:production) do
    YAML.safe_load(ERB.new(Rails.root.join("config/database.yml").read).result, aliases: true).fetch("production")
  end

  it "declares the databases this spec expects to find" do
    expect(production.keys).to include("primary", "cache", "queue", "cable")
  end

  it "has a schema file for each one" do
    missing = production.keys.reject do |name|
      file = name == "primary" ? "db/schema.rb" : "db/#{name}_schema.rb"
      Rails.root.join(file).exist?
    end

    expect(missing).to be_empty, "db:prepare would create these EMPTY: #{missing.join(', ')}"
  end

  it "gives each one the table its adapter reads" do
    { "cache" => "solid_cache_entries", "queue" => "solid_queue_jobs", "cable" => "solid_cable_messages" }.each do |name, table|
      expect(Rails.root.join("db/#{name}_schema.rb").read).to include(%(create_table "#{table}")), "#{name} lacks #{table}"
    end
  end
end
