require "rails_helper"

# The settings a CLIENT may know — and, much more importantly, the ones it may
# not.
RSpec.describe "Api::V1::Public::AppConfig", type: :request do
  def json = JSON.parse(response.body)

  # What the admin console does when Hamma9900 types a number in: one row.
  def set_support(value)
    Setting.find_or_initialize_by(key: "support_phone").update!(
      value: value, value_type: :string
    )
  end

  it "serves the support number to a GUEST, with no token at all" do
    set_support("+93700111222")

    get "/api/v1/public/app_config"

    expect(response).to have_http_status(:ok)
    expect(json.dig("app_config", "support_phone")).to eq("+93700111222")
  end

  # The point of it being a Setting: Hamma9900 types it into the console and
  # every installed app picks it up. It used to be a build-time constant in the
  # mobile app, so changing it meant a REBUILD.
  it "reflects a change made in the admin console with no deploy" do
    set_support("+93700111222")
    get "/api/v1/public/app_config"
    expect(json.dig("app_config", "support_phone")).to eq("+93700111222")

    set_support("+93700999888")
    get "/api/v1/public/app_config"
    expect(json.dig("app_config", "support_phone")).to eq("+93700999888")
  end

  # Blank is the shipped state and it must survive the trip. The app hides the
  # button rather than offering a number that rings nobody (UI_FINDINGS F-02),
  # so a nil or a missing key here would break that decision.
  it "serves a blank number as a blank string rather than omitting it" do
    set_support("")

    get "/api/v1/public/app_config"

    expect(json["app_config"]).to have_key("support_phone")
    expect(json.dig("app_config", "support_phone")).to eq("")
  end

  # THE ASSERTION THAT MATTERS. Most settings are the business's own numbers,
  # and some of them would tell a courier exactly how much we make on them.
  it "NEVER leaks the business's own numbers" do
    get "/api/v1/public/app_config"

    expect(json["app_config"].keys).to eq(%w[support_phone])
    expect(json["app_config"].keys).not_to include(
      "commission_rate", "default_credit_line", "cash_in_hand_limit",
      "delivery_base_fee", "trip_commission_rate", "dispatch_max_offers"
    )
  end

  # A guard against the lazy version of this endpoint — dumping the table.
  it "serves far fewer keys than the Setting table holds" do
    get "/api/v1/public/app_config"

    expect(json["app_config"].size).to be < Setting::DEFINITIONS.size / 4
  end
end
