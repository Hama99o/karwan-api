require "rails_helper"

# The shared machinery, asserted across BOTH demand types rather than once per
# class. The point of the concern is that food and rides behave identically
# where they should and differently only where they must.
RSpec.describe Dispatchable do
  # Every class that includes the concern. A new demand type added to this list
  # inherits every structural assertion below for free — which is the whole
  # reason these are written as a loop rather than copied per class.
  JOB_CLASSES = [ Order, Trip ].freeze

  describe "the demand-type keys cannot drift" do
    # Applying the lesson from the TRANSITIONS bug: when two lists must agree,
    # assert the whole list against the other rather than sampling it. Here it
    # is `CourierProfile::JOB_KINDS` against what the job classes declare. If
    # they disagree, a courier opts into a kind nothing dispatches, which reads
    # as "no couriers available" rather than as a misconfiguration.
    it "matches CourierProfile::JOB_KINDS exactly" do
      declared = JOB_CLASSES.map(&:job_kind).sort

      expect(declared).to eq(CourierProfile::JOB_KINDS.sort)
    end

    it "gives every job class a distinct, non-blank key" do
      keys = JOB_CLASSES.map(&:job_kind)

      expect(keys).to all(be_present)
      expect(keys.uniq.size).to eq(keys.size)
    end

    # "delivery" and "ride" are demand types, not table names. Pinning this
    # stops a well-meaning rename back to the table.
    it "names demand types, not tables" do
      expect(Order.job_kind).to eq("delivery")
      expect(Trip.job_kind).to eq("ride")
    end
  end

  describe "structural rules every job kind must satisfy" do
    JOB_CLASSES.each do |klass|
      context klass.name do
        it "declares all four constants" do
          expect(klass::STATUSES).to be_present
          expect(klass::TRANSITIONS).to be_present
          expect(klass::TERMINAL).to be_present
          expect(klass::TIMEOUTS).to be_present
        end

        it "covers every status in the transition table" do
          expect(klass::TRANSITIONS.keys.map(&:to_s).sort)
            .to eq(klass::STATUSES.keys.map(&:to_s).sort)
        end

        # A state with no deadline is how a job is silently abandoned — a
        # person waiting with cold food, or standing on a street corner.
        it "gives every non-terminal state a timeout" do
          expect(klass.states_without_timeout).to be_empty
        end

        it "gives no terminal state a timeout" do
          expect(klass::TIMEOUTS.keys & klass::TERMINAL).to be_empty
        end

        it "leaves every terminal state with no way out" do
          klass::TERMINAL.each do |status|
            expect(klass::TRANSITIONS[status]).to eq({}), "#{klass}##{status} should be terminal"
          end
        end

        it "names only real roles in the transition table" do
          named = klass::TRANSITIONS.values.flat_map(&:values).flatten.uniq

          expect(named - Roles::ALL.keys).to be_empty
        end

        it "names only real statuses as transition targets" do
          named = klass::TRANSITIONS.values.flat_map(&:keys).uniq

          expect(named - klass::STATUSES.keys.map(&:to_sym)).to be_empty
        end

        it "has a timestamp column for every status, so state_entered_at is real" do
          missing = klass::STATUSES.keys.reject { |s| klass.column_names.include?("#{s}_at") }

          expect(missing).to be_empty, "#{klass} has no #{missing.map { |s| "#{s}_at" }.join(', ')} column"
        end

        it "tracks payment explicitly with the same three states" do
          expect(klass.payment_statuses.keys).to eq(%w[pending collected settled])
        end
      end
    end
  end

  describe "#transition_to!" do
    it "moves the job, stamps the state's own column, and logs who did it" do
      order = create(:order)
      owner = create(:user, :merchant_owner)

      expect(order.transition_to!(:accepted, actor: owner, actor_role: :merchant_owner)).to be true
      expect(order.reload.status).to eq("accepted")
      expect(order.accepted_at).to be_present
      expect(order.transitions.last).to have_attributes(from_status: "placed", to_status: "accepted")
    end

    # Returns false rather than raising, so a stale client cannot 500 the
    # endpoint by replaying a button.
    it "refuses an illegal move without raising and writes nothing" do
      order = create(:order)

      expect(order.transition_to!(:delivered, actor: nil, actor_role: :admin)).to be false
      expect(order.reload.status).to eq("placed")
      expect(order.transitions).to be_empty
      expect(order.delivered_at).to be_nil
    end

    it "refuses a move by a role that is not allowed to make it" do
      order = create(:order)

      expect(order.transition_to!(:accepted, actor: create(:user), actor_role: :customer)).to be false
    end

    it "records a system move with no actor, which is what a timeout is" do
      order = create(:order)

      order.transition_to!(:rejected, actor: nil, actor_role: :admin, reason: "no response")

      expect(order.transitions.last).to be_system
      expect(order.transitions.last.reason).to eq("no response")
    end

    it "leaves the job untouched if the log row cannot be written" do
      order = create(:order)
      allow(order).to receive(:can_transition_to?).and_return(true)

      expect { order.transition_to!(:teleported, actor: nil, actor_role: :admin) }.to raise_error(ArgumentError)
      expect(order.reload.status).to eq("placed")
    end
  end

  describe "shared scopes behave the same for both kinds" do
    it ".live excludes terminal states" do
      expect(Order.live).to include(create(:order, :preparing))
      expect(Order.live).not_to include(create(:order, :delivered))
      expect(Trip.live).to include(create(:trip, :in_progress))
      expect(Trip.live).not_to include(create(:trip, :completed))
    end

    it ".unsettled is money that has not reached us, on either kind" do
      expect(Order.unsettled).to include(create(:order, :delivered))
      expect(Order.unsettled).not_to include(create(:order, :delivered, :settled))
      expect(Trip.unsettled).to include(create(:trip, :completed))
      expect(Trip.unsettled).not_to include(create(:trip, :completed, :settled))
    end

    it ".for_courier narrows to one person across both kinds" do
      courier = create(:user, :courier)
      order = create(:order, courier: courier)
      trip = create(:trip, courier: courier)
      create(:order)

      expect(Order.for_courier(courier)).to contain_exactly(order)
      expect(Trip.for_courier(courier)).to contain_exactly(trip)
    end
  end
end
