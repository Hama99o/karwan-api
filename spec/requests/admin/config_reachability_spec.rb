require "rails_helper"

# ═══ EVERY KNOB HAMMA9900 IS EXPECTED TO TURN MUST BE REACHABLE ════════════
#
# Correction 13 is that pricing stays deliberately stupid and **admin-tunable**:
# he retunes numbers weekly from the console with no deploy. **A knob he cannot
# reach means a deploy to change a number**, which is the one thing that design
# exists to prevent. So this is not housekeeping — it is whether the pricing
# model works in his hands.
#
# A setting can be unreachable in two different ways and **either one alone
# gives a false pass**, which is why both are asserted here:
#
#   1. NO ROW. `Setting.fetch` falls back to the definition's default when no
#      row exists, so the app runs correctly on a value he cannot see. The
#      console lists rows, not definitions, so the Config screen is simply
#      missing it. Nothing anywhere reports an error.
#   2. NO FIELD. A row that exists but is absent from the dashboard's form is
#      exactly as untunable as one that does not exist, and it fails at the
#      moment he tries to type in it.
RSpec.describe "Admin config reachability", type: :request do
  let(:admin) do
    AdminUser.create!(name: "Najibullah", email: "ops@karwan.af", password: "a-long-test-password")
  end

  before do
    post "/admin/login", params: { admin_user: { email: admin.email, password: "a-long-test-password" } }
  end

  describe "every definition becomes a row" do
    # ── THE GUARD THAT STOPS THIS PASSING BY HISTORY ────────────────────────
    #
    # A development database accumulates rows all day, so "they are all there"
    # can be true because somebody ran a seed in March rather than because
    # `seed_defaults!` works now. The assertion below therefore states what is
    # MISSING before it runs, so what follows measures the code rather than the
    # database's past.
    #
    # It is not zero rows: `spec/support/routing_default.rb` writes
    # `routing_distance_source` before every example, deliberately, so the
    # suite does not reach for OSRM. That is the only pre-existing row, and the
    # first version of this guard asserted `count == 0` and failed against a
    # perfectly good database — a checker measuring the wrong thing, which is
    # the trap this file is about.
    it "is missing almost everything before it is seeded" do
      expect(Setting.count).to be < Setting::DEFINITIONS.size
      expect(Setting.find_by(key: "delivery_base_fee")).to be_nil
    end

    it "materialises a row for every single definition" do
      expect(Setting.count).to be < Setting::DEFINITIONS.size

      Setting.seed_defaults!

      expect(Setting.pluck(:key)).to match_array(Setting::DEFINITIONS.keys)
    end

    it "gives each row the type and description the console renders" do
      Setting.seed_defaults!

      Setting.find_each do |setting|
        expect(setting.value_type).to be_present, "#{setting.key} has no value_type"
        expect(setting.description).to be_present, "#{setting.key} has no description"
      end
    end

    # Reference seeds are documented as safe to re-run after every deploy:
    # they refresh what is ours and never overwrite a number he tuned.
    it "never overwrites a value he has already tuned" do
      Setting.seed_defaults!
      Setting.find_by!(key: "delivery_base_fee").update!(value: "999")

      Setting.seed_defaults!

      expect(Setting.find_by!(key: "delivery_base_fee").value).to eq("999")
    end
  end

  describe "every row is editable in the console" do
    before { Setting.seed_defaults! }

    it "lists them on the Config screen" do
      get "/admin/settings"

      expect(response).to have_http_status(:ok)
    end

    it "accepts a new value for every key, one by one" do
      Setting.find_each do |setting|
        patch "/admin/settings/#{setting.id}", params: { setting: { value: setting.value.to_s } }

        expect(response).to have_http_status(:redirect), "#{setting.key} could not be saved"
      end
    end

    # ── THE EXAMPLE ABOVE CANNOT SEE A MISSING INPUT, AND THAT IS THE POINT ──
    #
    # `Admin::SettingsController#update` is a custom action that permits
    # `:value` itself, so a PATCH succeeds whatever the dashboard renders.
    # Emptying `FORM_ATTRIBUTES` therefore left every example above GREEN while
    # the edit page had **no field to type in** — precisely the "row exists,
    # field does not" failure this file's header describes, undetected by the
    # file that describes it.
    #
    # So this asserts the page HE OPENS: the form must actually contain an
    # input bound to `setting[value]`.
    it "renders an input he can type a value into" do
      setting = Setting.find_by!(key: "delivery_base_fee")

      get "/admin/settings/#{setting.id}/edit"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("setting[value]")
    end
  end

  # ── THE KNOBS THAT LANDED TODAY ─────────────────────────────────────────
  #
  # Each of these exists SO THAT HE CAN TURN IT. One landing without a console
  # row is a feature that is built, shipped, green, and unusable — and it would
  # have read as done.
  describe "the knobs added on 2026-09-17" do
    before { Setting.seed_defaults! }

    TODAYS_KNOBS = %w[
      shortage_multiplier_enabled shortage_multiplier max_total_multiplier
      courier_topup_enabled courier_min_earnings_per_km
    ].freeze

    it "puts every one of them in front of him" do
      TODAYS_KNOBS.each do |key|
        expect(Setting.find_by(key: key)).to be_present, "#{key} never reaches the console"
      end
    end

    it "gives a radius row to every vehicle, generated rather than typed" do
      VehicleTypes::ALL.each_key do |vehicle|
        key = Dispatch::OfferRadius.key_for(vehicle)

        expect(Setting.find_by(key: key)).to be_present, "#{vehicle} has no radius he can tune"
      end
    end

    # A switch he can see but not flip is the same as no switch. Booleans go
    # through the same string `value` column as everything else, so this is
    # worth proving rather than assuming.
    it "lets him actually turn the shortage switch on" do
      setting = Setting.find_by!(key: "shortage_multiplier_enabled")

      patch "/admin/settings/#{setting.id}", params: { setting: { value: "true" } }

      expect(Setting.fetch("shortage_multiplier_enabled")).to be(true)
    end

    it "lets him actually change a number the pricing reads" do
      setting = Setting.find_by!(key: "courier_min_earnings_per_km")

      patch "/admin/settings/#{setting.id}", params: { setting: { value: "25" } }

      expect(Setting.fetch("courier_min_earnings_per_km")).to eq(25)
    end
  end
end
