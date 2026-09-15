require "rails_helper"

RSpec.describe DeviceToken, type: :model do
  describe "validations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to validate_presence_of(:token) }
  end

  describe ".register!" do
    let(:user) { create(:user) }

    it "creates a token" do
      record = described_class.register!(user: user, token: "ExponentPushToken[abc]", platform: :android)

      expect(record).to be_persisted
      expect(record).to have_attributes(user_id: user.id, platform: "android", active: true)
      expect(record.last_seen_at).to be_present
    end

    # Re-registering must not fail. The app re-registers on every launch, and a
    # unique-constraint error there would break the launch, not the push.
    it "is idempotent for the same token" do
      described_class.register!(user: user, token: "ExponentPushToken[abc]", platform: :android)

      expect {
        described_class.register!(user: user, token: "ExponentPushToken[abc]", platform: :android)
      }.not_to change(described_class, :count)
    end

    # The same physical tablet gets handed between staff, and the merchant's
    # order alert must follow whoever is signed in. Leaving it on the previous
    # user means the alert goes to someone who went home.
    it "moves an existing token to whoever is signed in now" do
      first = create(:user)
      second = create(:user)
      described_class.register!(user: first, token: "ExponentPushToken[abc]", platform: :android)

      record = described_class.register!(user: second, token: "ExponentPushToken[abc]", platform: :android)

      expect(record.user_id).to eq(second.id)
      expect(described_class.where(token: "ExponentPushToken[abc]").count).to eq(1)
    end

    it "reactivates a token that had been deactivated" do
      record = described_class.register!(user: user, token: "ExponentPushToken[abc]", platform: :android)
      record.deactivate!

      described_class.register!(user: user, token: "ExponentPushToken[abc]", platform: :android)

      expect(record.reload.active).to be true
    end
  end

  describe "#deactivate!" do
    it "marks the token inactive without deleting it" do
      record = create(:device_token)

      record.deactivate!

      expect(record.reload.active).to be false
      expect(described_class.find(record.id)).to eq(record)
    end
  end

  describe ".active" do
    it "excludes deactivated tokens, which would waste a push" do
      live = create(:device_token)
      create(:device_token).deactivate!

      expect(described_class.active).to contain_exactly(live)
    end
  end

  describe "platforms" do
    it "covers both stores, because v0 ships Android and iOS" do
      expect(described_class.platforms.keys).to eq(%w[android ios])
    end
  end
end
