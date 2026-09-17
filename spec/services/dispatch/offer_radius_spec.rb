require "rails_helper"

RSpec.describe Dispatch::OfferRadius do
  describe ".km" do
    it "reads the vehicle's own row" do
      Setting.find_or_initialize_by(key: "dispatch_max_offer_radius_km_bicycle")
             .update!(value: "2.5", value_type: :decimal)

      expect(described_class.km(:bicycle)).to eq(BigDecimal("2.5"))
    end

    it "does not let one vehicle's row move another's" do
      Setting.find_or_initialize_by(key: "dispatch_max_offer_radius_km_bicycle")
             .update!(value: "2.5", value_type: :decimal)

      expect(described_class.km(:car)).to eq(BigDecimal(Setting::DEFAULT_OFFER_RADIUS_KM))
    end

    it "takes a string as readily as a symbol, because an enum reads back as one" do
      Setting.find_or_initialize_by(key: "dispatch_max_offer_radius_km_zarang")
             .update!(value: "15", value_type: :decimal)

      expect(described_class.km("zarang")).to eq(BigDecimal("15"))
    end

    # ── THE FALLBACK GOES TO THE GLOBAL ROW, NOT TO ZERO ────────────────────
    #
    # The opposite of `VehicleTypes.carries?`, deliberately, and the asymmetry
    # is the reason: a capacity that fails closed costs one dispatch, while a
    # RADIUS that fails closed costs every dispatch for that vehicle — a silent
    # outage that reads as "dispatch is broken". See Dispatch::OfferRadius.
    context "a vehicle with no row of its own" do
      it "falls back to the global ceiling rather than refusing everything" do
        Setting.find_or_initialize_by(key: "dispatch_max_offer_radius_km")
               .update!(value: "9", value_type: :decimal)

        expect(described_class.km(:hovercraft)).to eq(BigDecimal("9"))
      end

      it "answers for a nil vehicle instead of raising" do
        expect(described_class.km(nil)).to eq(BigDecimal(Setting::DEFAULT_OFFER_RADIUS_KM))
      end
    end
  end

  # ── THE TWO LISTS CANNOT DRIFT, BECAUSE THERE IS ONLY ONE ────────────────
  #
  # The per-vehicle rows are generated from `VehicleTypes::ALL`, so a vehicle
  # added to the enum arrives with a ceiling already. This asserts the property
  # rather than the six names: a seventh vehicle should make nothing here go
  # red, and a hand-typed list would.
  describe "the definitions" do
    it "gives every known vehicle a row" do
      VehicleTypes::ALL.each_key do |vehicle|
        expect(Setting::DEFINITIONS).to have_key(described_class.key_for(vehicle))
      end
    end

    it "names the vehicle in the description, because the console is a list of keys" do
      expect(Setting::DEFINITIONS[described_class.key_for(:rishka)][:description])
        .to include("rishka")
    end

    it "keeps the global row as the fallback it now is" do
      expect(Setting::DEFINITIONS).to have_key(described_class::GLOBAL_KEY)
    end
  end

  # `Setting.seed_defaults!` is what puts a row in front of Hamma9900 — a
  # definition he cannot see in the console is a knob he cannot turn.
  describe "the console" do
    it "materialises a row per vehicle he can edit" do
      Setting.seed_defaults!

      VehicleTypes::ALL.each_key do |vehicle|
        expect(Setting.find_by(key: described_class.key_for(vehicle))).to be_present
      end
    end
  end
end
