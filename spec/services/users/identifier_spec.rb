require "rails_helper"

# ONE FIELD, EITHER IDENTIFIER.
#
# Hamma9900: *"login simple with email and password or phone number and
# password."* Two fields, or a toggle between them, is a decision the user has
# to make and a screen they can get wrong.
RSpec.describe Users::Identifier do
  describe ".resolve" do
    it "reads an @ as an email, downcased" do
      resolved = described_class.resolve("  Ahmad@Gmail.com ")

      expect(resolved).to be_email
      expect(resolved.value).to eq("ahmad@gmail.com")
    end

    it "reads anything else as a phone, normalised" do
      resolved = described_class.resolve("0700000801")

      expect(resolved).to be_phone
      expect(resolved.value).to eq("+93700000801")
    end

    it "is nil for nothing to resolve" do
      expect(described_class.resolve("")).to be_nil
      expect(described_class.resolve(nil)).to be_nil
    end
  end

  describe ".find_user" do
    let!(:user) { create(:user, phone: "+93700000801", email: "ahmad@gmail.com") }

    # THE POINT OF NORMALISING BEFORE THE LOOKUP. Without it the second form
    # looks like a stranger, and a registration would hand them a second
    # account — with its own wallet and no way to merge the two.
    it "finds one account from either form of its number" do
      expect(described_class.find_user("+93700000801")).to eq(user)
      expect(described_class.find_user("0700000801")).to eq(user)
      expect(described_class.find_user("0093700000801")).to eq(user)
    end

    it "finds it by email, whatever the case" do
      expect(described_class.find_user("AHMAD@GMAIL.COM")).to eq(user)
    end

    it "is nil for an identifier nobody holds" do
      expect(described_class.find_user("+93700009999")).to be_nil
      expect(described_class.find_user("nobody@example.com")).to be_nil
    end

    # A deleted account is not an account. Soft delete exists because order
    # history must survive, not so somebody can sign back in.
    it "does not find a discarded account" do
      user.discard!

      expect(described_class.find_user("+93700000801")).to be_nil
    end
  end
end
