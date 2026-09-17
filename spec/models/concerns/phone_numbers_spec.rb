require "rails_helper"

# ONE CANONICAL FORM, because the phone is an identity.
#
# `0700000801` and `+93700000801` are the same person. If the unique index does
# not know that, the second form gets a SECOND ACCOUNT — with its own orders,
# its own wallet, and no way to merge them, because a merge would have to
# decide which history is real.
RSpec.describe PhoneNumbers do
  describe ".normalise" do
    it "leaves an international number alone" do
      expect(described_class.normalise("+93700000801")).to eq("+93700000801")
    end

    # THE ONE THAT MATTERS: what an Afghan user actually types.
    it "turns a local number into an international one" do
      expect(described_class.normalise("0700000801")).to eq("+93700000801")
    end

    # The leading zero is a domestic dialling prefix, not part of the number.
    # Keeping it would make `+930700000801`, which nobody can ring.
    it "drops the domestic dialling zero rather than keeping it" do
      # by-design: normalise returns a non-empty string, so this is a real fact about it.
      expect(described_class.normalise("0700000801")).not_to include("+930")
    end

    # `00` and `+` are the same thing, and which one appears depends on the
    # keypad somebody used.
    it "treats a 00 prefix as a plus" do
      expect(described_class.normalise("0093700000801")).to eq("+93700000801")
    end

    it "strips what humans type for readability" do
      expect(described_class.normalise(" 070 000 08-01 ")).to eq("+93700000801")
      expect(described_class.normalise("(070) 000 0801")).to eq("+93700000801")
    end

    it "is nil for nothing, rather than raising on a text field" do
      expect(described_class.normalise("")).to be_nil
      expect(described_class.normalise(nil)).to be_nil
      expect(described_class.normalise("   ")).to be_nil
    end

    # IDEMPOTENT, because it runs on every save and a second pass must not
    # rewrite what the first produced.
    it "is unchanged by being applied twice" do
      once = described_class.normalise("0700000801")

      expect(described_class.normalise(once)).to eq(once)
    end
  end

  describe ".plausible?" do
    it "accepts both forms of a real number" do
      expect(described_class).to be_plausible("+93700000801")
      expect(described_class).to be_plausible("0700000801")
    end

    it "refuses something that is not a number at all" do
      expect(described_class).not_to be_plausible("hello")
      expect(described_class).not_to be_plausible("+93")
      expect(described_class).not_to be_plausible("")
    end

    # LOOSE ON PURPOSE. A client that refuses a number the server would have
    # accepted is a user who cannot sign in at all, and Afghan numbering has
    # more shapes than any regex here would admit.
    it "accepts an unfamiliar country code rather than deciding it is impossible" do
      expect(described_class).to be_plausible("+12025550123")
    end
  end
end
