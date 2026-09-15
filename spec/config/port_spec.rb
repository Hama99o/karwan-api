require "rails_helper"

# The API's default port, asserted where it cannot be forgotten.
#
# Rails ships `port ENV.fetch("PORT", 3000)`, and on this machine 3000 is a
# DIFFERENT live application. So an API started without `-p 3017` bound the
# wrong port and a health check reported a green API that was a stranger's —
# `qa.sh doctor` did exactly that. The convention used to live in the README,
# which is why it was missed.
#
# This reads the config file rather than booting Puma: the DSL is evaluated by
# the server, not by the app, so there is nothing to ask at runtime. It still
# fails if someone restores the framework default, which is the point.
RSpec.describe "the server's default port" do
  # COMMENTS STRIPPED FIRST. The comment in puma.rb quotes the old
  # `port ENV.fetch("PORT", 3000)` to explain what was wrong with it, and the
  # first version of this spec matched that quotation instead of the code —
  # so it failed against a correct file. A checker that reads prose is
  # measuring the wrong thing, whichever way it lands.
  let(:puma_config) do
    Rails.root.join("config/puma.rb").read.lines.reject { |line| line.strip.start_with?("#") }.join
  end

  it "is 3017, so starting the server wrongly is not possible" do
    default = puma_config[/port\s+ENV\.fetch\(\s*"PORT",\s*([A-Za-z_0-9]+)\s*\)/, 1]
    expect(default).to eq("DEFAULT_PORT")

    literal = puma_config[/DEFAULT_PORT\s*=\s*(\d+)/, 1]
    expect(literal).to eq("3017")
  end

  it "never falls back to 3000, which is another application on this box" do
    expect(puma_config).not_to match(/ENV\.fetch\(\s*"PORT",\s*3000\s*\)/)
  end

  # A link in a development email or an Active Storage URL pointing at 3000
  # would open that other application.
  it "is the same port development URL generation assumes" do
    development = Rails.root.join("config/environments/development.rb")
                       .read.lines.reject { |line| line.strip.start_with?("#") }.join

    expect(development).to include('port: 3017')
    expect(development).not_to match(/port:\s*3000/)
  end
end
