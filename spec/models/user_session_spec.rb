require "rails_helper"

RSpec.describe UserSession, type: :model do
  describe "validations" do
    it { is_expected.to belong_to(:user) }

    it "requires a unique token digest" do
      create(:user_session, token_digest: described_class.digest("abc"))
      duplicate = build(:user_session, token_digest: described_class.digest("abc"))

      expect(duplicate).not_to be_valid
    end
  end

  describe ".digest" do
    # HMAC-SHA256, not bcrypt, and the reason matters: bcrypt salts per row and
    # therefore cannot be looked up by digest at all. With a 256-bit random
    # token there is nothing to brute force, so a deterministic keyed digest is
    # both correct and indexable.
    it "is deterministic, so a token can be looked up" do
      expect(described_class.digest("abc")).to eq(described_class.digest("abc"))
    end

    it "differs per token" do
      expect(described_class.digest("abc")).not_to eq(described_class.digest("abd"))
    end

    it "is keyed on secret_key_base, so rotating it invalidates every session" do
      before = described_class.digest("abc")
      allow(Rails.application).to receive(:secret_key_base).and_return("a-different-key")

      expect(described_class.digest("abc")).not_to eq(before)
    end

    it "handles a nil token without raising" do
      expect { described_class.digest(nil) }.not_to raise_error
    end
  end

  describe ".issue!" do
    let(:user) { create(:user) }

    it "returns the record and the plaintext token exactly once" do
      record, token = described_class.issue!(user)

      expect(record).to be_persisted
      expect(token).to be_present
    end

    it "never stores the plaintext" do
      record, token = described_class.issue!(user)

      expect(record.token_digest).not_to eq(token)
      expect(record.token_digest).to eq(described_class.digest(token))
    end

    # 256 bits. The entropy, not the KDF, is what makes these unguessable.
    it "issues a high-entropy token" do
      _record, token = described_class.issue!(user)

      expect(token.length).to be >= 40
    end

    it "issues a different token every time" do
      tokens = 5.times.map { described_class.issue!(user).last }

      expect(tokens.uniq.size).to eq(5)
    end

    it "records the device, so a person can see and revoke their sessions" do
      record, _token = described_class.issue!(user, device_name: "Pixel 6a", platform: "android")

      expect(record).to have_attributes(device_name: "Pixel 6a", platform: "android")
    end

    it "sets an expiry" do
      record, _token = described_class.issue!(user)

      expect(record.expires_at).to be_within(5.seconds).of(described_class::TTL.from_now)
    end
  end

  describe ".authenticate" do
    let(:user) { create(:user) }

    it "finds the session for a valid token" do
      record, token = described_class.issue!(user)

      expect(described_class.authenticate(token)).to eq(record)
    end

    it "returns nil for an unknown token" do
      described_class.issue!(user)

      expect(described_class.authenticate("not-a-real-token")).to be_nil
    end

    it "returns nil for a blank token rather than matching anything" do
      described_class.issue!(user)

      expect(described_class.authenticate(nil)).to be_nil
      expect(described_class.authenticate("")).to be_nil
    end

    it "refuses a revoked session" do
      record, token = described_class.issue!(user)
      record.revoke!

      expect(described_class.authenticate(token)).to be_nil
    end

    it "refuses an expired session" do
      record, token = described_class.issue!(user)
      record.update!(expires_at: 1.second.ago)

      expect(described_class.authenticate(token)).to be_nil
    end

    # A session with no expiry is a permanent credential. The scope allows nil
    # deliberately (an admin-issued long-lived session), so this pins that it is
    # intentional rather than an oversight.
    it "accepts a session with no expiry at all" do
      record, token = described_class.issue!(user)
      record.update!(expires_at: nil)

      expect(described_class.authenticate(token)).to eq(record)
    end
  end

  describe "#revoke!" do
    it "marks the session revoked" do
      record = create(:user_session)

      expect { record.revoke! }.to change { record.reload.revoked_at }.from(nil)
    end
  end

  describe "#touch_usage!" do
    it "updates last_used_at without touching updated_at" do
      record = create(:user_session, last_used_at: 1.hour.ago)
      previously = record.updated_at

      record.touch_usage!

      expect(record.reload.last_used_at).to be_within(5.seconds).of(Time.current)
      expect(record.updated_at).to eq(previously)
    end
  end

  # ── WHICH MODE THIS DEVICE IS IN ────────────────────────────────────────────
  #
  # This lived on `users`, which meant one human had one mode everywhere. The
  # specs below are the three things that has to mean.
  describe "#switch_role!" do
    let(:user) { create(:user, :customer) }
    let(:session) { described_class.issue!(user).first }

    it "switches to a role the user holds" do
      user.user_roles.create!(role: :courier)

      expect(session.switch_role!(:courier)).to be true
      expect(session.reload.active_role).to eq("courier")
    end

    # Returns false rather than raising, so a stale client asking for a role
    # that was revoked gets a clean refusal instead of a 500.
    it "refuses a role the user does not hold, and does not raise" do
      expect(session.switch_role!(:admin)).to be false
      expect(session.reload.active_role).to eq("customer")
    end

    it "refuses a role that is not a role at all" do
      expect(session.switch_role!("wizard")).to be false
      expect(session.reload.active_role).to eq("customer")
    end

    # ONE DEVICE AT A TIME. A merchant keeps a tablet on the counter and a
    # phone in his pocket; flipping the phone must not flip the tablet.
    it "leaves the person's other devices in the mode they were in" do
      user.user_roles.create!(role: :merchant_owner)
      tablet = described_class.issue!(user, device_name: "counter tablet").first
      tablet.switch_role!(:merchant_owner)

      session.switch_role!(:customer)

      expect(tablet.reload.active_role).to eq("merchant_owner")
    end

    # ...but the choice IS remembered, because a reinstall is a new session and
    # a courier must not land back in the customer tab after one.
    it "writes the choice through as the user's preference" do
      user.user_roles.create!(role: :courier)

      expect { session.switch_role!(:courier) }
        .to change { user.reload.last_active_role }.from("customer").to("courier")
    end

    # The false return must mean ONE thing. `update` returning false made "you
    # do not hold that role" and "the write failed" indistinguishable, so a
    # failed save was reported to the user as a permissions problem.
    it "raises rather than returning false when the write itself fails" do
      user.user_roles.create!(role: :courier)
      allow(session).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(session))

      expect { session.switch_role!(:courier) }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "leaves the preference alone when the session write fails" do
      user.user_roles.create!(role: :courier)
      allow(session).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(session))

      expect { session.switch_role!(:courier) rescue nil }
        .not_to change { user.reload.last_active_role }
    end
  end

  describe ".issue! and the mode a new device opens in" do
    it "opens in the customer tab for a brand new account" do
      record, = described_class.issue!(create(:user))

      expect(record.active_role).to eq("customer")
    end

    # THE REASON THE COLUMN ON `users` WAS KEPT RATHER THAN DROPPED. A
    # reinstall is a new session, so without a preference a courier reinstalling
    # mid-shift would open in the customer tab with no jobs in it.
    it "opens where the person left off" do
      user = create(:user, :courier, last_active_role: :courier)

      record, = described_class.issue!(user)

      expect(record.active_role).to eq("courier")
    end

    # A demoted courier must not be seeded into a tab that has nothing in it
    # and no way to explain why.
    it "falls back to customer when the person no longer holds that role" do
      user = create(:user, last_active_role: :courier)
      user.user_roles.create!(role: :customer)

      record, = described_class.issue!(user)

      expect(record.active_role).to eq("customer")
    end
  end

  describe "revoking one device does not revoke the others" do
    it "leaves sibling sessions alive" do
      user = create(:user)
      phone_record, phone_token = described_class.issue!(user, device_name: "phone")
      _tablet_record, tablet_token = described_class.issue!(user, device_name: "tablet")

      phone_record.revoke!

      expect(described_class.authenticate(phone_token)).to be_nil
      expect(described_class.authenticate(tablet_token)).to be_present
    end
  end
end
