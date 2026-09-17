require "rails_helper"

RSpec.describe Pricing::ShortageMultiplier do
  def set(key, value)
    Setting.find_or_initialize_by(key: key)
           .update!(value: value.to_s, value_type: Setting::DEFINITIONS.fetch(key)[:type])
  end

  describe ".requested" do
    it "is 1 when nobody has turned it on, which is the shipping state" do
      expect(described_class.requested).to eq(1)
    end

    # TWO ROWS RATHER THAN ONE, and this is the example that earns the second.
    # A single number would mean turning the storm off depends on somebody
    # remembering to type 1.0 back — and the night a storm ends is exactly when
    # nobody is thinking about the admin console.
    it "ignores a left-over number once the switch is off" do
      set("shortage_multiplier", "1.8")

      expect(described_class.requested).to eq(1)
    end

    it "is the number once the switch is on" do
      set("shortage_multiplier", "1.8")
      set("shortage_multiplier_enabled", "true")

      expect(described_class.requested).to eq(BigDecimal("1.8"))
    end

    # A shortage may raise a fee and must never lower one. A fraction typed
    # here would cut the courier's pay in a storm, which is the exact opposite
    # of what the switch is for.
    it "never goes below 1, whatever is typed" do
      set("shortage_multiplier", "0.4")
      set("shortage_multiplier_enabled", "true")

      expect(described_class.requested).to eq(1)
    end
  end

  describe ".effective — the cap" do
    before do
      set("shortage_multiplier_enabled", "true")
      set("max_total_multiplier", "2.0")
    end

    it "leaves a sane number alone" do
      set("shortage_multiplier", "1.5")

      expect(described_class.effective(tier: 1)).to eq(BigDecimal("1.5"))
    end

    # THE FAILURE THIS EXISTS TO PREVENT: a mistyped 10 where 1.5 was meant, in
    # a console with no second pair of eyes.
    it "clamps a mistyped number so the customer's total cannot pass the cap" do
      set("shortage_multiplier", "10")

      expect(described_class.effective(tier: 1)).to eq(BigDecimal("2.0"))
    end

    # The cap is on shortage x tier, so a premium order leaves less room for
    # the shortage — the customer's TOTAL is what the cap is about.
    it "leaves room for the tier that will multiply on top" do
      set("shortage_multiplier", "10")

      expect(described_class.effective(tier: BigDecimal("1.3")))
        .to eq(BigDecimal("2.0") / BigDecimal("1.3"))
    end

    it "says when it bit, and when it did not" do
      set("shortage_multiplier", "10")
      expect(described_class).to be_capped(tier: 1)

      set("shortage_multiplier", "1.5")
      expect(described_class).not_to be_capped(tier: 1)
    end

    # Fails SAFE rather than dividing by zero: a cap of 0 or a tier of 0 is a
    # mistyped row, and the answer is to ignore the nonsense rather than to
    # raise inside a quote a customer is waiting on.
    it "does not divide by a zero anybody typed" do
      set("shortage_multiplier", "1.5")
      set("max_total_multiplier", "0")

      expect { described_class.effective(tier: 1) }.not_to raise_error
      expect(described_class.effective(tier: 0)).to eq(BigDecimal("1.5"))
    end
  end
end
