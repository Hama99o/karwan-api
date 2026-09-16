require "rails_helper"

RSpec.describe CourierProfile, type: :model do
  describe "validations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:verified_by).optional }

    # A pending applicant is allowed to be incomplete — they are still filling
    # the form. An APPROVED courier without identity or a guarantor is the state
    # that must be impossible, because that is someone we have handed cash and
    # goods to with nothing to trace.
    it "allows a pending profile to be incomplete" do
      expect(build(:courier_profile, full_name: nil, national_id_number: nil)).to be_valid
    end

    it "requires identity and a guarantor once approved" do
      profile = build(:courier_profile, :approved, full_name: nil)
      expect(profile).not_to be_valid

      profile = build(:courier_profile, :approved, national_id_number: nil)
      expect(profile).not_to be_valid

      profile = build(:courier_profile, :approved, guarantor_name: nil)
      expect(profile).not_to be_valid

      profile = build(:courier_profile, :approved, guarantor_phone: nil)
      expect(profile).not_to be_valid
    end

    # An approved courier who accepts no kind of work can never be offered
    # anything. That is not a courier, it is a silent dead end in the dispatch
    # loop — and it would read as "no couriers available" rather than as a
    # misconfigured account.
    it "refuses an approved courier who accepts no kind of job" do
      profile = build(:courier_profile, :approved, accepted_job_kinds: [])

      expect(profile).not_to be_valid
      expect(profile.errors[:accepted_job_kinds]).to be_present
    end

    # A typo here makes the courier undispatchable and looks like a supply
    # problem rather than a data problem.
    it "rejects an unknown job kind" do
      profile = build(:courier_profile, accepted_job_kinds: %w[delivery teleportation])

      expect(profile).not_to be_valid
      expect(profile.errors[:accepted_job_kinds].join).to include("teleportation")
    end

    it "accepts every declared job kind" do
      expect(build(:courier_profile, accepted_job_kinds: described_class::JOB_KINDS)).to be_valid
    end
  end

  describe "#dispatchable_for?" do
    it "is true for an approved, available courier who takes that kind" do
      profile = create(:courier_profile, :dispatchable)

      expect(profile.dispatchable_for?(:delivery)).to be true
    end

    it "is false for a kind they do not accept" do
      profile = create(:courier_profile, :dispatchable)

      expect(profile.dispatchable_for?(:ride)).to be false
    end

    it "is false when off shift, however well approved" do
      profile = create(:courier_profile, :approved)

      expect(profile.dispatchable_for?(:delivery)).to be false
    end

    it "is false when not approved, however available" do
      profile = create(:courier_profile, :available)

      expect(profile.dispatchable_for?(:delivery)).to be false
    end

    it "accepts a string as well as a symbol" do
      profile = create(:courier_profile, :dispatchable)

      expect(profile.dispatchable_for?("delivery")).to be true
    end

    it "is false for a kind that does not exist rather than raising" do
      profile = create(:courier_profile, :dispatchable)

      expect(profile.dispatchable_for?(:teleportation)).to be false
    end
  end

  describe ".dispatchable_for" do
    it "returns only couriers eligible for that demand type" do
      food = create(:courier_profile, :dispatchable)
      trips = create(:courier_profile, :dispatchable, :takes_rides)
      both = create(:courier_profile, :dispatchable, :takes_both)
      create(:courier_profile, :available)  # not approved
      create(:courier_profile, :approved)   # off shift

      expect(described_class.dispatchable_for(:delivery)).to contain_exactly(food, both)
      expect(described_class.dispatchable_for(:ride)).to contain_exactly(trips, both)
    end

    # One person, one pool. A courier taking both kinds is the point of the
    # whole two-demand-type design — food is spiky, and rides fill the gaps.
    it "offers a courier who takes both to either queue" do
      both = create(:courier_profile, :dispatchable, :takes_both)

      expect(described_class.dispatchable_for(:delivery)).to include(both)
      expect(described_class.dispatchable_for(:ride)).to include(both)
    end
  end

  describe "#location_fresh?" do
    # A fix older than STALE_AFTER is not a location, it is a memory. Dispatch
    # must not offer a job based on where someone was an hour ago.
    it "is true for a recent fix" do
      expect(create(:courier_profile, :available)).to be_location_fresh
    end

    it "is false for a stale fix" do
      expect(create(:courier_profile, :stale_location)).not_to be_location_fresh
    end

    it "is false when there has never been a fix" do
      expect(create(:courier_profile)).not_to be_location_fresh
    end
  end

  describe "#coordinates" do
    it "returns the pair when both are present" do
      profile = create(:courier_profile, :available)

      expect(profile.coordinates).to eq([ profile.last_latitude, profile.last_longitude ])
    end

    it "returns nil rather than a half pair" do
      expect(create(:courier_profile).coordinates).to be_nil
      expect(create(:courier_profile, last_latitude: 34.5).coordinates).to be_nil
    end
  end

  describe "#record_location!" do
    it "stores the fix and stamps the time" do
      profile = create(:courier_profile)

      profile.record_location!(latitude: 34.5553, longitude: 69.2075)

      expect(profile.reload.coordinates).to eq([ BigDecimal("34.5553"), BigDecimal("69.2075") ])
      expect(profile).to be_location_fresh
    end
  end

  describe "#approve!" do
    let(:admin) { create(:user, :admin) }

    # Approval is a human decision and must carry a name. A nil approver on an
    # approved courier is how "who let this person in?" becomes unanswerable.
    it "records who approved and when" do
      profile = create(:courier_profile)

      profile.approve!(by: admin)

      expect(profile.reload).to have_attributes(
        verification_status: "approved", verified_by_id: admin.id
      )
      expect(profile.verified_at).to be_present
    end

    it "clears a previous rejection reason, so the record is not contradictory" do
      profile = create(:courier_profile)
      profile.reject!(by: admin, reason: "documents unreadable")

      profile.approve!(by: admin)

      expect(profile.reload.rejection_reason).to be_nil
    end
  end

  describe "#reject!" do
    let(:admin) { create(:user, :admin) }

    it "records the rejection with a reason and a name" do
      profile = create(:courier_profile, :available)

      profile.reject!(by: admin, reason: "no guarantor")

      expect(profile.reload).to have_attributes(
        verification_status: "rejected", rejection_reason: "no guarantor",
        verified_by_id: admin.id
      )
    end

    # A rejected courier who is still flagged available would keep appearing in
    # dispatch queries. Taking them off shift is part of rejecting them.
    it "takes them off shift" do
      profile = create(:courier_profile, :available)

      profile.reject!(by: admin, reason: "no guarantor")

      expect(profile.reload.is_available).to be false
    end
  end

  describe "vehicle types" do
    it "covers the ways a courier actually travels in Kabul" do
      expect(described_class.vehicle_types.keys).to eq(%w[motorbike bicycle car on_foot rishka zarang])
      # THE INTEGERS ARE THE CONTRACT, not the order of the keys. The two new
      # types were appended rather than slotted in beside the bicycle, because
      # these values are stored and renumbering them would turn every car in
      # the database into a rishka.
      expect(described_class.vehicle_types).to eq(
        "motorbike" => 0, "bicycle" => 1, "car" => 2, "on_foot" => 3,
        "rishka" => 4, "zarang" => 5
      )
    end
  end
end
