require "rails_helper"

RSpec.describe User, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:phone) }
    it { is_expected.to validate_presence_of(:locale) }
    it { is_expected.to validate_inclusion_of(:locale).in_array(described_class::LOCALES) }

    it "requires a unique phone, because the phone IS the identity" do
      create(:user, phone: "+93770000001")
      duplicate = build(:user, phone: "+93770000001")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:phone]).to be_present
    end

    it "supports all three locales and rejects a fourth" do
      expect(described_class::LOCALES).to contain_exactly("ps", "fa", "en")
      expect(build(:user, locale: "ur")).not_to be_valid
    end
  end

    # Karwan is FOR Afghanistan, but like Hatiwal it is not technically
    # restricted to it — the app works for a neighbouring number without that
    # being advertised. Hamma9900: "this app is only for afg but as we have
    # done for hatiwal its open in side country pakistan but we did not mention
    # it".
    #
    # So: no country validator, no format validator, no geofence. This example
    # exists to stop someone adding a `+93` format rule in good faith, which
    # would lock out every user across the border with no error a person could
    # act on.
    it "accepts a phone number from outside Afghanistan" do
      expect(build(:user, phone: "+923001234567")).to be_valid   # Pakistan
      expect(build(:user, phone: "+989121234567")).to be_valid   # Iran
      expect(build(:user, phone: "+93700123456")).to be_valid    # Afghanistan
    end

  describe "associations" do
    it { is_expected.to have_many(:user_roles).dependent(:destroy) }
    it { is_expected.to have_many(:addresses).dependent(:destroy) }
    it { is_expected.to have_many(:user_sessions).dependent(:destroy) }
    it { is_expected.to have_many(:device_tokens).dependent(:destroy) }
    it { is_expected.to have_one(:courier_profile).dependent(:destroy) }
    it { is_expected.to have_one(:courier_wallet).dependent(:destroy) }

    it "refuses to destroy a user who has order history" do
      order = create(:order)

      expect(order.customer.destroy).to be false
      expect(order.customer.errors[:base]).to be_present
    end
  end

  describe "enums" do
    it "defines the four roles once, shared with UserRole and UserSession" do
      expect(described_class.last_active_roles.keys).to eq(%w[customer courier merchant_owner admin])
      expect(described_class.last_active_roles).to eq(UserRole.roles)
      # All three must agree, or a switch writes a role the other side cannot
      # read back.
      expect(UserSession.active_roles).to eq(UserRole.roles)
    end

    it "defines account status" do
      expect(described_class.statuses.keys).to eq(%w[active suspended])
    end
  end

  describe "#role?" do
    let(:user) { create(:user) }

    it "is true for a held role" do
      create(:user_role, user: user, role: :courier)

      expect(user.role?(:courier)).to be true
    end

    it "is false for a role the user does not hold" do
      expect(user.role?(:admin)).to be false
    end

    it "accepts a string as well as a symbol" do
      create(:user_role, user: user, role: :admin)

      expect(user.role?("admin")).to be true
    end
  end

  # ── WHO THIS PERSON IS ALLOWED TO BE ────────────────────────────────────────
  #
  # Hamma9900's asymmetry: partner → customer is automatic, customer → partner
  # never is.
  describe "#grant_role!" do
    let(:user) { create(:user) }

    it "grants the role asked for" do
      expect { user.grant_role!(:courier) }
        .to change { user.reload.role?(:courier) }.from(false).to(true)
    end

    # "The client account opens if we have restaurant or rider or driver
    # account automatic, because it's not a big thing." A courier who cannot
    # order food breaks the premise the shared pool rests on.
    it "grants the customer role alongside any partner role" do
      user.grant_role!(:courier)

      expect(user.reload.role?(:customer)).to be true
    end

    it "is idempotent, so it is safe on every save" do
      user.grant_role!(:courier)

      expect { user.grant_role!(:courier) }.not_to change { user.reload.user_roles.count }
    end
  end

  describe "#revoke_role!" do
    let(:user) { create(:user) }

    it "takes a partner role away" do
      user.grant_role!(:merchant_owner)

      expect { user.revoke_role!(:merchant_owner) }
        .to change { user.reload.role?(:merchant_owner) }.from(true).to(false)
    end

    # THE GUARD, TESTED DIRECTLY. Nothing in the app revokes `customer` today,
    # so the merchant-ownership specs pass whether this guard exists or not —
    # which makes them no test of it at all. Losing the ability to buy food is
    # not a consequence anyone intends, and the next caller should not have to
    # rediscover that.
    it "refuses to take the customer role away" do
      user.grant_role!(:courier)

      user.revoke_role!(:customer)

      expect(user.reload.role?(:customer)).to be true
    end

    it "does nothing for a role the person never held" do
      expect { user.revoke_role!(:courier) }.not_to raise_error
    end
  end

  # Switching moved to `UserSession`, because which mode the app is in is a
  # fact about a DEVICE. What is left here is the preference that seeds the
  # next new session — see spec/models/user_session_spec.rb.
  describe "#last_active_role" do
    it "does not answer for a device, and says so by not existing" do
      expect(create(:user)).not_to respond_to(:switch_role!)
    end
  end

  describe "#phone_verified?" do
    it "is true once phone_verified_at is set" do
      expect(create(:user).phone_verified?).to be true
    end

    it "is false for an unverified user" do
      expect(create(:user, :unverified).phone_verified?).to be false
    end
  end

  describe "#display_name" do
    it "uses the name when present" do
      expect(build(:user, name: "Ahmad Karimi").display_name).to eq("Ahmad Karimi")
    end

    # A customer who never typed a name still has to be addressable in the
    # admin console and on the rider's screen.
    it "falls back to the phone when the name is blank" do
      user = build(:user, name: "", phone: "+93770000009")

      expect(user.display_name).to eq("+93770000009")
    end
  end

  describe ".with_role" do
    it "returns only users holding that role" do
      courier = create(:user, :courier)
      create(:user, :customer)

      expect(described_class.with_role(:courier)).to contain_exactly(courier)
    end
  end

  describe "soft delete" do
    it "keeps a discarded user out of .kept but still findable" do
      user = create(:user)
      user.discard!

      expect(described_class.kept).not_to include(user)
      expect(described_class.discarded).to include(user)
      expect(described_class.find(user.id)).to eq(user)
    end
  end
end
