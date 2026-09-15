require "rails_helper"

RSpec.describe OtpVerification, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:phone) }
    it { is_expected.to validate_presence_of(:code_digest) }
    it { is_expected.to validate_presence_of(:expires_at) }
  end

  describe ".issue!" do
    it "returns the record and the plaintext code exactly once" do
      record, code = described_class.issue!("+93770000001")

      expect(record).to be_persisted
      expect(code).to match(/\A\d{6}\z/)
    end

    # The plaintext is for the SMS sender and nothing else. If it were stored,
    # a database read would hand over every live code.
    it "never stores the plaintext" do
      record, code = described_class.issue!("+93770000001")

      expect(record.code_digest).not_to eq(code)
      expect(record.attributes.values.map(&:to_s)).not_to include(code)
    end

    it "digests with bcrypt, which is verifiable" do
      record, code = described_class.issue!("+93770000001")

      expect(BCrypt::Password.new(record.code_digest)).to eq(code)
    end

    it "sets a short expiry" do
      record, _code = described_class.issue!("+93770000001")

      expect(record.expires_at).to be_within(5.seconds).of(described_class::TTL.from_now)
    end

    # Zero-padded, so "000123" stays six characters. Trimming the leading zero
    # would make a sixth of all codes five digits long and unverifiable.
    it "zero-pads a small number to the full length" do
      allow(SecureRandom).to receive(:random_number).and_return(123)

      _record, code = described_class.issue!("+93770000001")

      expect(code).to eq("000123")
    end
  end

  describe "#verify" do
    let(:phone) { "+93770000001" }

    it "accepts the right code and consumes it" do
      record, code = described_class.issue!(phone)

      expect(record.verify(code)).to be true
      expect(record.reload).to be_consumed
    end

    it "rejects the wrong code" do
      record, _code = described_class.issue!(phone)

      expect(record.verify("000000")).to be false
      expect(record.reload).not_to be_consumed
    end

    # Six digits is 10^6 guesses, which is nothing. The attempt counter — not
    # the digest — is the actual protection, so it must move on EVERY call.
    it "counts a failed attempt" do
      record, _code = described_class.issue!(phone)

      expect { record.verify("000000") }.to change { record.reload.attempts_count }.by(1)
    end

    # Counting only failures would let someone probe indefinitely by mixing in
    # one good guess to reset their standing.
    it "counts a successful attempt too" do
      record, code = described_class.issue!(phone)

      expect { record.verify(code) }.to change { record.reload.attempts_count }.by(1)
    end

    it "refuses once the attempts are exhausted, even with the right code" do
      record, code = described_class.issue!(phone)
      record.update!(attempts_count: described_class::MAX_ATTEMPTS)

      expect(record.verify(code)).to be false
    end

    it "does not increment past the limit once exhausted" do
      record, _code = described_class.issue!(phone)
      record.update!(attempts_count: described_class::MAX_ATTEMPTS)

      expect { record.verify("000000") }.not_to change { record.reload.attempts_count }
    end

    it "refuses an expired code even when it is correct" do
      record, code = described_class.issue!(phone)
      record.update!(expires_at: 1.second.ago)

      expect(record.verify(code)).to be false
    end

    # A code is single-use. Replay is how an intercepted SMS becomes a login
    # long after the fact.
    it "refuses a code that has already been used" do
      record, code = described_class.issue!(phone)
      expect(record.verify(code)).to be true

      expect(record.verify(code)).to be false
    end

    it "handles a nil or blank guess without raising" do
      record, _code = described_class.issue!(phone)

      expect(record.verify(nil)).to be false
      expect(record.verify("")).to be false
    end
  end

  describe "predicates" do
    it "#expired? tracks the expiry boundary" do
      expect(build(:otp_verification, expires_at: 1.second.from_now)).not_to be_expired
      expect(build(:otp_verification, expires_at: 1.second.ago)).to be_expired
    end

    it "#usable? requires unconsumed, unexpired and attempts remaining" do
      expect(build(:otp_verification)).to be_usable
      expect(build(:otp_verification, :consumed)).not_to be_usable
      expect(build(:otp_verification, :expired)).not_to be_usable
      expect(build(:otp_verification, :attempts_exhausted)).not_to be_usable
    end
  end

  describe "scopes" do
    it ".live excludes consumed and expired codes" do
      live = create(:otp_verification)
      create(:otp_verification, :consumed)
      create(:otp_verification, :expired)

      expect(described_class.live).to contain_exactly(live)
    end

    it ".for_phone narrows to one number" do
      mine = create(:otp_verification, phone: "+93770000001")
      create(:otp_verification, phone: "+93770000002")

      expect(described_class.for_phone("+93770000001")).to contain_exactly(mine)
    end
  end

  # Recorded as an open gap in docs/NOTES.md and repeated here so the suite
  # carries the warning too: nothing limits how many codes can be SENT to a
  # number. As written, the request endpoint is an SMS bill and a way to harass
  # any phone in Afghanistan. It must not ship without a send limit.
  describe "send throttling (NOT IMPLEMENTED — must not ship without it)" do
    it "currently allows unlimited sends to one number" do
      10.times { described_class.issue!("+93770000001") }

      expect(described_class.for_phone("+93770000001").count).to eq(10)
    end
  end
end
