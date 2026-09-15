require "rails_helper"

RSpec.describe Settlement, type: :model do
  describe "validations" do
    it { is_expected.to belong_to(:courier) }
    it { is_expected.to belong_to(:counted_by).optional }
    it { is_expected.to validate_presence_of(:settled_at) }

    # Free text as well as an optional user reference, because the person
    # counting cash in Kabul may not have an account — and "who counted this"
    # must never be null.
    it "requires the name of the person who counted" do
      expect(build(:settlement, counted_by_name: nil)).not_to be_valid
    end

    it "does not require them to have an account" do
      settlement = build(:settlement, counted_by: nil, counted_by_name: "Najibullah (Kabul office)")

      expect(settlement).to be_valid
    end
  end

  describe "expected AND counted, both stored" do
    # Mismatches are normal — change floats, rounding, a note left with a
    # customer. UNEXPLAINED mismatches are theft. You cannot tell the two apart
    # if only one number was ever written down, which is why both columns exist.
    it "#variance is what was counted minus what was expected" do
      expect(create(:settlement, :short).variance).to eq(-50)
      expect(create(:settlement, :over).variance).to eq(50)
      expect(create(:settlement).variance).to eq(0)
    end

    it "#balanced? is true only on an exact match" do
      expect(create(:settlement)).to be_balanced
      expect(create(:settlement, :short)).not_to be_balanced
      expect(create(:settlement, :over)).not_to be_balanced
    end

    # Short and over are not the same problem. Short is money missing; over is
    # a bookkeeping error or someone else's change. Both need finding, and the
    # admin screen colours them differently.
    it "#short? distinguishes missing money from surplus" do
      expect(create(:settlement, :short)).to be_short
      expect(create(:settlement, :over)).not_to be_short
      expect(create(:settlement)).not_to be_short
    end
  end

  describe ".mismatched" do
    it "surfaces every settlement that did not balance, in either direction" do
      short = create(:settlement, :short)
      over = create(:settlement, :over)
      create(:settlement)

      expect(described_class.mismatched).to contain_exactly(short, over)
    end
  end

  describe ".newest_first" do
    it "orders by when the cash was counted, not when the row was written" do
      old = create(:settlement, settled_at: 2.days.ago, created_at: 1.hour.ago)
      recent = create(:settlement, settled_at: 1.hour.ago, created_at: 2.days.ago)

      expect(described_class.newest_first).to eq([ recent, old ])
    end
  end

  describe "currency" do
    it "stores it explicitly and refuses one it does not know" do
      expect(build(:settlement, currency: "USD")).not_to be_valid
      expect(build(:settlement, currency: "AFN")).to be_valid
    end
  end
end
