require "rails_helper"

RSpec.describe Setting, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:key) }

    it "requires a unique key" do
      create(:setting, key: "commission_rate")

      expect(build(:setting, key: "commission_rate")).not_to be_valid
    end
  end

  describe ".fetch" do
    # A silent nil here becomes a ZERO FEE in production, which is far worse
    # than a 500 in development. Raising is the deliberate choice.
    it "raises on an unknown key rather than returning nil" do
      expect { described_class.fetch("commision_rate") }  # deliberate typo
        .to raise_error(KeyError, /commision_rate/)
    end

    it "names the constant to edit in the error, so the fix is obvious" do
      expect { described_class.fetch("nope") }
        .to raise_error(KeyError, /Setting::DEFINITIONS/)
    end

    it "returns the declared default when no row exists" do
      expect(described_class.fetch("commission_rate")).to eq(BigDecimal("0.125"))
    end

    it "prefers a stored row over the default" do
      described_class.create!(key: "commission_rate", value: "0.2", value_type: :decimal)

      expect(described_class.fetch("commission_rate")).to eq(BigDecimal("0.2"))
    end

    # value_type exists so no reader has to guess. A decimal read as a string is
    # how "0.125" silently becomes zero in an arithmetic expression.
    describe "casting" do
      it "returns a BigDecimal for a money or rate setting, never a Float" do
        value = described_class.fetch("delivery_base_fee")

        expect(value).to be_a(BigDecimal)
        expect(value).to eq(50)
      end

      it "returns an Integer for an integer setting" do
        expect(described_class.fetch("dispatch_offer_ttl_sec")).to eq(60)
        expect(described_class.fetch("dispatch_offer_ttl_sec")).to be_a(Integer)
      end

      it "returns a String for a string setting" do
        expect(described_class.fetch("support_phone")).to eq("")
      end

      it "casts a stored integer string to an Integer" do
        described_class.create!(key: "dispatch_max_offers", value: "9", value_type: :integer)

        expect(described_class.fetch("dispatch_max_offers")).to eq(9)
      end
    end

    # BigDecimal arithmetic is exact; Float is not. A commission computed in
    # Float is how a total ends up a hundredth off and nobody can explain it.
    it "produces exact arithmetic, not floating point drift" do
      rate = described_class.fetch("commission_rate")

      expect(rate * 400).to eq(50)
      expect((rate * 333).round(2)).to eq(BigDecimal("41.63"))
    end
  end

  describe "DEFINITIONS" do
    it "declares every key the app reads, with a type" do
      described_class::DEFINITIONS.each do |key, definition|
        expect(definition[:type]).to be_present, "#{key} has no type"
        expect(described_class.value_types.keys).to include(definition[:type].to_s)
      end
    end

    it "gives every money setting a currency, so nothing is summed blind" do
      # The `trip_*` fare keys are gone to `pricing_rates` — a ride fare varies
      # by the vehicle class the passenger chose, which a key-value table
      # cannot express without 48 rows. Their currency is asserted on the rate
      # rows instead, in spec/models/pricing_rate_spec.rb.
      money_keys = %w[delivery_base_fee delivery_fee_per_km delivery_minimum_fee
                      cash_in_hand_limit default_credit_line]

      money_keys.each do |key|
        expect(described_class::DEFINITIONS.dig(key, :currency)).to eq("AFN"), "#{key} has no currency"
      end
    end

    it "gives every key a description, because admin edits these without context" do
      described_class::DEFINITIONS.each do |key, definition|
        expect(definition[:description]).to be_present, "#{key} has no description"
      end
    end

    # Every one of these is a number Hamma9900 said he would tune weekly.
    # Hard-coding any of them means a deploy each time he changes his mind.
    it "covers the numbers that get tuned, for both demand types" do
      expect(described_class::DEFINITIONS.keys).to include(
        "commission_rate", "delivery_base_fee", "delivery_fee_per_km", "delivery_minimum_fee",
        "cash_in_hand_limit", "default_credit_line", "eta_average_speed_kmh",
        "dispatch_offer_ttl_sec", "dispatch_max_offers", "support_phone",
        "trip_commission_rate"
      )
    end

    # ── THE RULE THAT KEEPS TWO CONFIG MECHANISMS FROM BECOMING A MESS ───────
    #
    # `Setting` holds SCALARS; `pricing_rates` holds anything that varies by
    # vehicle. Asserted, because the failure mode is silent: a tariff key
    # re-added here would be a second source of truth for a fare, and code
    # would have to decide which to trust — the same reason the flat
    # `delivery_fee` was replaced rather than kept alongside the distance
    # formula.
    it "holds no per-vehicle tariff, because those are rows" do
      tariff_keys = described_class::DEFINITIONS.keys.grep(/\A(trip|ride)_.*(fare|base|per_km|per_minute|minimum)/)

      expect(tariff_keys).to be_empty
    end

    # ── THE DECISION, ASSERTED WHERE IT IS DECLARED ──────────────────────────
    #
    # Hamma9900: distances are not measured by roads, and straight-line is
    # unfair. The ROW was flipped hours after he said so and the DEFAULT was
    # not, which means the next fresh database would have silently priced on
    # crow flight again — the same failure a second time.
    #
    # The suite overrides the effective value per example
    # (spec/support/routing_default.rb) so that hundreds of tests are not
    # exercising the router's failure path while appearing to test the happy
    # one. This asserts the declaration rather than the behaviour.
    it "prices on roads by default, because that is the decision" do
      expect(described_class::DEFINITIONS.dig("routing_distance_source", :default))
        .to eq(Routing::Route::OSRM)
    end

    # The commission rate STAYS here, and that is the distinction: it is the
    # same share for every class, so it is a scalar.
    it "keeps the ride commission, which does not vary by vehicle" do
      expect(described_class::DEFINITIONS).to have_key("trip_commission_rate")
    end

    it "every declared default casts without raising" do
      described_class::DEFINITIONS.each_key do |key|
        expect { described_class.fetch(key) }.not_to raise_error, "#{key} failed to cast"
      end
    end
  end

  describe ".seed_defaults!" do
    it "creates a row for every definition" do
      described_class.seed_defaults!

      expect(described_class.count).to eq(described_class::DEFINITIONS.size)
    end

    it "is idempotent, so a redeploy does not duplicate rows" do
      described_class.seed_defaults!

      expect { described_class.seed_defaults! }.not_to change(described_class, :count)
    end

    # This is the one that matters on a redeploy: seeding must not silently
    # reset a number the owner tuned last week.
    it "does not overwrite a value an admin has changed" do
      described_class.seed_defaults!
      described_class.find_by(key: "delivery_base_fee").update!(value: "150")

      described_class.seed_defaults!

      expect(described_class.fetch("delivery_base_fee")).to eq(150)
    end

    it "refreshes the description and currency, which are ours not theirs" do
      described_class.create!(key: "delivery_base_fee", value: "150", value_type: :decimal,
                              description: "stale text")

      described_class.seed_defaults!

      row = described_class.find_by(key: "delivery_base_fee")
      expect(row.description).to eq(described_class::DEFINITIONS.dig("delivery_base_fee", :description))
      expect(row.currency).to eq("AFN")
    end
  end

  describe "#typed_value" do
    it "casts the row's own value by its declared type" do
      row = described_class.create!(key: "commission_rate", value: "0.15", value_type: :decimal)

      expect(row.typed_value).to eq(BigDecimal("0.15"))
    end
  end
end
