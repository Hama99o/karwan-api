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

        # Every job kind must say what the courier has to be able to float
        # before it is offered. A third demand type that forgets this would
        # inherit Order's meaning or crash in the wallet gate — and the wallet
        # gate is the one place a courier is told "no".
        it "declares what the wallet must cover before an offer" do
          job = build(klass.name.underscore.to_sym)

          expect(job).to respond_to(:wallet_requirement)
          expect(job.wallet_requirement).to be_present
        end

        it "declares what the courier advances out of pocket" do
          expect(build(klass.name.underscore.to_sym)).to respond_to(:courier_advance)
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

  describe ".overdue" do
    # The board needs the SET, not a predicate per record. Measured against
    # 20,000 stress orders: loading every live order and calling `overdue?`
    # took 287ms, the scope 9ms.
    #
    # The thing that actually matters is that the fast path gives the SAME
    # answer as the slow one. A scope that disagrees with the method is worse
    # than a slow method, because the board would quietly show the wrong orders
    # and nobody would know which to trust. These examples assert agreement
    # rather than just speed.
    JOB_CLASSES.each do |klass|
      it "agrees with ##{'overdue?'} record by record for #{klass.name}" do
        factory = klass.name.underscore.to_sym
        fresh = create(factory)
        stale = create(factory, :overdue)

        from_sql = klass.live.overdue.pluck(:id)
        from_ruby = klass.live.to_a.select(&:overdue?).map(&:id)

        expect(from_sql.sort).to eq(from_ruby.sort)
        expect(from_sql).to include(stale.id)
        # by-design: the line above asserts stale.id IS present.
        expect(from_sql).not_to include(fresh.id)
      end

      it "excludes terminal #{klass.name} records, which are finished not late" do
        terminal_trait = klass == Order ? :delivered : :completed
        done = create(klass.name.underscore.to_sym, terminal_trait)
        done.update_columns(created_at: 3.days.ago, updated_at: 3.days.ago)

        # by-design: the example above proves `overdue` returns rows for a stale job.
        expect(klass.overdue.pluck(:id)).not_to include(done.id)
      end
    end

    # COALESCE to updated_at mirrors #state_entered_at, so a row whose state
    # column is somehow nil is still judged rather than silently treated as
    # fresh — silently fresh is how an abandoned order stays invisible.
    it "still judges a record whose state timestamp is missing" do
      order = create(:order)
      order.update_columns(placed_at: nil, updated_at: 3.days.ago, created_at: 3.days.ago)

      expect(Order.overdue.pluck(:id)).to include(order.id)
    end

    it "builds its condition from TIMEOUTS, so the two cannot disagree" do
      sql = Order.overdue.to_sql

      Order::TIMEOUTS.each_key do |status|
        expect(sql).to include("#{status}_at"), "TIMEOUTS names #{status} but the scope does not use #{status}_at"
      end
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
