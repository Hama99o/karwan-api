require "rails_helper"

# The routing data is made by one osrm-backend version and must be served by
# the same one. `:latest` could move under it on any boot (25 Sept 2026).
RSpec.describe "one OSRM version" do
  def images(path) = Rails.root.join(path).read.lines.reject { _1 =~ /\A\s*#/ }.join.scan(%r{ghcr\.io/project-osrm/osrm-backend\S*})

  it "pins the served image by digest" do
    expect(images("config/deploy.yml")).to all(match(/@sha256:\h{64}\z/))
    expect(images("config/deploy.yml")).not_to be_empty
  end

  it "uses that same image wherever this repo runs OSRM" do
    served = images("config/deploy.yml").uniq
    expect(images("docs/RUNBOOK.md").map { _1.delete_suffix("\\") }.uniq).to eq(served)
  end
end
