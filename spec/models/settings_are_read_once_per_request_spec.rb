require "rails_helper"

# Setting.fetch went to the database on every call, and dispatch read about
# two per candidate courier. Setting::RequestCache holds a value for the rest
# of the request or job; a write clears it.
RSpec.describe "settings are read once per request" do
  before { Setting::RequestCache.reset }

  def queries_for
    n = 0
    counter = ->(*, payload) { n += 1 if payload[:sql].include?(%("settings")) }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    n
  end

  it "reads a setting from the database once, however often it is asked for" do
    expect(queries_for { 5.times { Setting.fetch("delivery_base_fee") } }).to eq(1)
  end

  it "sees a value written in the same request straight away" do
    Setting.fetch("delivery_base_fee")
    Setting.find_or_initialize_by(key: "delivery_base_fee").update!(value: "73", value_type: :decimal)

    expect(Setting.fetch("delivery_base_fee")).to eq(73)
  end

  it "starts every request with nothing cached" do
    Setting.fetch("delivery_base_fee")
    Setting::RequestCache.reset # what Rails does around every request and job

    expect(queries_for { Setting.fetch("delivery_base_fee") }).to eq(1)
  end
end
