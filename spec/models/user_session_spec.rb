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
