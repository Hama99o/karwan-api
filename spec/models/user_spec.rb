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

  # ── TWO IDENTIFIERS, ONE PASSWORD ───────────────────────────────────────────
  #
  # Hamma9900: *"We will not use OTP. We will have login simple with email and
  # password or phone number and password."*
  #
  # The PHONE is the guaranteed identifier — NOT NULL and unique since the first
  # migration, because a courier has to ring somebody. The EMAIL is the
  # additional one. That asymmetry fits the market: a Play Store install
  # requires a Google account, so a Play user has Gmail, while a SIDELOADED
  # user (an APK over Bluetooth, which is common here) may have none, and on a
  # SHARED HANDSET the Gmail may belong to somebody's brother.
  describe "the identifiers" do
    it "stores an email downcased, because nobody types it the same way twice" do
      user = create(:user, email: " Ahmad@Gmail.COM ")

      expect(user.email).to eq("ahmad@gmail.com")
    end

    it "refuses a second account on the same email, whatever the case" do
      create(:user, email: "ahmad@gmail.com")

      expect(build(:user, email: "AHMAD@gmail.com")).not_to be_valid
    end

    # ── MANY ACCOUNTS WITH NO EMAIL MUST COEXIST ────────────────────────────
    #
    # Postgres treats NULLs as distinct in a unique index, which is the
    # behaviour we want and the reason the column can be nullable at all.
    # Asserted rather than assumed, because the alternative — fabricating
    # `+93700000801@something` to satisfy a NOT NULL — is worse than a null:
    # it is unique, it looks real, and one day somebody registers that address
    # for real.
    it "allows any number of accounts with no email" do
      expect(create(:user, email: nil)).to be_persisted
      expect(create(:user, email: nil)).to be_persisted
      expect(User.where(email: nil).count).to be >= 2
    end

    it "treats a blank email as no email rather than as a value" do
      expect(create(:user, email: "")).to be_persisted
      expect(create(:user, email: "   ").email).to be_nil
    end

    it "refuses something that is not an address" do
      expect(build(:user, email: "not-an-address")).not_to be_valid
    end

    # THE SAME FAILURE ON THE OTHER FIELD, and worse: a second account gets its
    # own wallet.
    it "normalises the phone before it is stored" do
      expect(create(:user, phone: "0700000901").phone).to eq("+93700000901")
    end

    it "refuses a second account on the same number written differently" do
      create(:user, phone: "+93700000901")

      expect(build(:user, phone: "0700000901")).not_to be_valid
    end
  end

  describe "the password" do
    it "is checked against the stored digest, never in the clear" do
      user = create(:user, password: "a-long-enough-password")

      expect(user.encrypted_password).not_to include("a-long-enough-password")
      expect(user.valid_password?("a-long-enough-password")).to be true
      expect(user.valid_password?("something else")).to be false
    end

    # Every account created before passwords existed signed in with a code.
    # They are not broken and not locked out — they reset, which is what
    # `:recoverable` is for.
    it "knows when an account has none" do
      expect(create(:user, :passwordless).password_set?).to be false
      expect(create(:user, password: "a-long-enough-password").password_set?).to be true
    end
  end
end
