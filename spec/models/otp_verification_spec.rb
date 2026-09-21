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
      # by-design: a record's attribute list is never empty.
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
    # ── FROZEN, BECAUSE THIS RACED THE THING IT WAS MEASURING ─────────────
    #
    # Written against a live clock with a one-second margin, it failed in a full
    # suite run on a loaded box and passed on its own: `build` and the predicate
    # straddled the boundary. This file takes 40 seconds for 30 examples —
    # bcrypt at cost 12 — so a second elapsing between two lines is ordinary
    # here, not exotic.
    #
    # A flaky example is the sibling of a check that cannot fail: one is ignored
    # because it never speaks, the other because it cries wolf, and both end
    # with somebody scrolling past a red line. Freezing tests the boundary
    # EXACTLY rather than widening the margin until the race is merely unlikely.
    it "#expired? tracks the expiry boundary" do
      freeze_time do
        expect(build(:otp_verification, expires_at: 1.second.from_now)).not_to be_expired
        expect(build(:otp_verification, expires_at: 1.second.ago)).to be_expired

        # ── AND THE BOUNDARY ITSELF, WHICH THIS NEVER TESTED ──────────────
        #
        # One second either side does not test a boundary; `expires_at ==
        # Time.current` is the only input where `<=` and `<` differ, and
        # flipping the predicate to `<` left all thirty examples in this file
        # green. So the example was named for a case it did not cover.
        #
        # A live clock could not have asserted this — hitting the exact instant
        # is what freezing buys, over and above killing the flake.
        #
        # `<=` is the right direction: a code that expires at T is unusable AT
        # T, not one second after it. The safer side of a one-time code.
        expect(build(:otp_verification, expires_at: Time.current)).to be_expired,
                                                                     "a code is usable at the instant it expires"
      end
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

  # SMS is one of exactly two recurring costs in v0, so an unthrottled request
  # endpoint is not merely a security gap — it is someone else spending the
  # owner's money, and a way to harass any number in Afghanistan.
  describe "send throttling" do
    let(:phone) { "+93770000001" }

    it "allows the burst limit and refuses the next" do
      limit = Setting.fetch("otp_max_sends_per_window")

      limit.times { described_class.issue!(phone) }

      expect { described_class.issue!(phone) }.to raise_error(described_class::Throttled)
      expect(described_class.for_phone(phone).count).to eq(limit)
    end

    # The row is not even created when throttled: the thing being protected is
    # the SMS, and a caller must not be able to fill the table either.
    it "creates nothing when throttled" do
      Setting.fetch("otp_max_sends_per_window").times { described_class.issue!(phone) }

      expect { described_class.issue!(phone) rescue nil }
        .not_to change { described_class.for_phone(phone).count }
    end

    # "Too many attempts" with no number is the dead end that loses a
    # first-time user — and every user here arrived through a conversation.
    it "says when to try again" do
      Setting.fetch("otp_max_sends_per_window").times { described_class.issue!(phone) }

      begin
        described_class.issue!(phone)
      rescue described_class::Throttled => e
        expect(e.retry_after_seconds).to be_between(1, Setting.fetch("otp_send_window_minutes") * 60)
        expect(e.message).to match(/retry in \d+s/)
      end
    end

    it "allows again once the window has passed" do
      Setting.fetch("otp_max_sends_per_window").times { described_class.issue!(phone) }
      described_class.for_phone(phone).update_all(created_at: 20.minutes.ago)

      expect { described_class.issue!(phone) }.not_to raise_error
    end

    # The burst window sliding open must not uncap the day. Otherwise a patient
    # caller sends three every fifteen minutes forever.
    it "still refuses once the daily cap is reached, however patient the caller" do
      daily = Setting.fetch("otp_max_sends_per_day")
      daily.times do |i|
        described_class.create!(phone: phone, code_digest: BCrypt::Password.create("123456"),
                                expires_at: described_class::TTL.from_now, created_at: (i + 1).hours.ago)
      end

      expect { described_class.issue!(phone) }.to raise_error(described_class::Throttled)
    end

    it "throttles per number, so one abused number does not block everyone" do
      Setting.fetch("otp_max_sends_per_window").times { described_class.issue!(phone) }

      expect { described_class.issue!("+93770000002") }.not_to raise_error
    end

    it "is tunable without a deploy" do
      Setting.seed_defaults!
      Setting.find_by!(key: "otp_max_sends_per_window").update!(value: "1")

      described_class.issue!(phone)

      expect { described_class.issue!(phone) }.to raise_error(described_class::Throttled)
    end

    describe ".send_allowance" do
      it "reports headroom for a fresh number" do
        expect(described_class.send_allowance(phone)).to eq({ allowed: true, retry_after_seconds: nil })
      end

      it "reports the wait once exhausted" do
        Setting.fetch("otp_max_sends_per_window").times { described_class.issue!(phone) }
        allowance = described_class.send_allowance(phone)

        expect(allowance[:allowed]).to be false
        expect(allowance[:retry_after_seconds]).to be_positive
      end
    end
  end
end
