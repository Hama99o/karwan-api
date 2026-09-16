require "rails_helper"

# Every predicate and every scope on the order policy.
#
# `OrderPolicy` was reached only through request specs until now, which is
# thinner than it looks: a request spec proves the endpoints that exist behave,
# and says nothing about a predicate NOTHING CALLS. That is how `track?` came
# to be written, be correct, and be dead — docs/NOTES.md records the same shape
# from edu-safi, "the correct scope existed, was correct, and was never
# consulted". A policy spec is the gate that can catch it.
RSpec.describe OrderPolicy do
  let(:customer) { create(:user, :customer) }
  let(:owner) { create(:user, :merchant_owner) }
  let(:merchant) { create(:merchant, owner: owner) }
  let(:courier) { create(:user, :courier) }
  let(:admin) { create(:user, :admin) }
  let(:stranger) { create(:user, :customer) }

  let(:order) { create(:order, customer: customer, merchant: merchant, courier: courier) }

  describe "#show?" do
    # Three audiences, three different RELATIONSHIPS to one record. Holding a
    # role is not the qualification — being on this order is.
    it "allows the customer who placed it, the merchant's owner, the assigned courier and admin" do
      expect(described_class.new(customer, order).show?).to be true
      expect(described_class.new(owner, order).show?).to be true
      expect(described_class.new(courier, order).show?).to be true
      expect(described_class.new(admin, order).show?).to be true
    end

    it "refuses another customer" do
      expect(described_class.new(stranger, order).show?).to be false
    end

    # Being a courier does not mean seeing every order — only the assigned one.
    it "refuses a courier who is not the one assigned" do
      other_courier = create(:user, :courier)

      expect(described_class.new(other_courier, order).show?).to be false
    end

    it "refuses the owner of a different merchant" do
      other_owner = create(:user, :merchant_owner)
      create(:merchant, owner: other_owner)

      expect(described_class.new(other_owner, order).show?).to be false
    end

    it "refuses a guest" do
      expect(described_class.new(nil, order).show?).to be false
    end
  end

  describe "#create?" do
    it "allows anyone holding the customer role, and refuses a guest" do
      expect(described_class.new(customer, Order).create?).to be true
      expect(described_class.new(admin, Order).create?).to be true
      expect(described_class.new(nil, Order).create?).to be false
    end

    # A COURIER AND A RESTAURANT OWNER MAY BUY FOOD, and this example used to
    # assert the opposite. It was right when it was written — a partner held
    # only their partner role — and wrong the moment Hamma9900's rule landed:
    # "the client account open if we have restaurant or rider or driver account
    # automatic, because it's not a big thing."
    #
    # The premise the shared pool rests on is that these are ONE HUMAN with
    # several capabilities: the same person delivers a meal at 13:00 and buys
    # one at 20:00. A policy that refused him would have made the platform's
    # own couriers its only customers who cannot order.
    it "allows a courier and a merchant owner, because they are customers too" do
      expect(courier.role?(:customer)).to be true
      expect(described_class.new(courier, Order).create?).to be true
      expect(described_class.new(owner, Order).create?).to be true
    end

    # ...and it is still the CUSTOMER role doing the allowing, not the partner
    # one. Somebody holding only `courier` — which the app can no longer
    # produce, but an import or a fix-up script could — is refused.
    it "refuses somebody who holds a partner role and nothing else" do
      # Written as a direct delete because `revoke_role!` REFUSES to take the
      # customer role away — which is the point of that guard. This is the
      # state only an import or a fix-up script could leave behind, and the
      # policy still answers correctly in it.
      courier.user_roles.where(role: UserRole.roles["customer"]).destroy_all

      expect(described_class.new(courier.reload, Order).create?).to be false
    end
  end

  describe "#cancel?" do
    # WHO and WHETHER are two different questions and this predicate answers
    # only the first. The state machine owns the second, and is consulted here
    # rather than duplicated.
    it "allows the customer while the order is still cancellable" do
      expect(described_class.new(customer, order).cancel?).to be true
    end

    it "refuses the customer once the state machine says no" do
      picked_up = create(:order, :picked_up, customer: customer, merchant: merchant)

      expect(described_class.new(customer, picked_up).cancel?).to be false
    end

    it "refuses another customer even while the order is cancellable" do
      expect(described_class.new(stranger, order).cancel?).to be false
    end

    # The merchant has its own reject/cancel path with a reason attached; it
    # must not reach the customer's.
    it "refuses the merchant's owner and the courier" do
      expect(described_class.new(owner, order).cancel?).to be false
      expect(described_class.new(courier, order).cancel?).to be false
    end
  end

  describe "the board predicates" do
    # One per action rather than a single `update?`, so each can be refused
    # independently — and so the state machine stays the only authority on
    # ordering.
    it "allows the merchant's own owner and admin" do
      %i[accepted? rejected? preparing? ready?].each do |predicate|
        expect(described_class.new(owner, order).public_send(predicate)).to be true
        expect(described_class.new(admin, order).public_send(predicate)).to be true
      end
    end

    it "refuses the customer, the courier, another merchant's owner and a guest" do
      other_owner = create(:user, :merchant_owner)
      create(:merchant, owner: other_owner)

      %i[accepted? rejected? preparing? ready?].each do |predicate|
        expect(described_class.new(customer, order).public_send(predicate)).to be false
        expect(described_class.new(courier, order).public_send(predicate)).to be false
        expect(described_class.new(other_owner, order).public_send(predicate)).to be false
        expect(described_class.new(nil, order).public_send(predicate)).to be false
      end
    end
  end

  describe "#track?" do
    it "allows the customer, the merchant's owner and admin while the order is live" do
      expect(described_class.new(customer, order).track?).to be true
      expect(described_class.new(owner, order).track?).to be true
      expect(described_class.new(admin, order).track?).to be true
    end

    # The liveness check is the reason this predicate exists at all. Without
    # it, a customer could watch a courier for the rest of their shift from an
    # order delivered last week.
    it "refuses EVERYONE on a terminal order, including admin" do
      %i[delivered cancelled failed].each do |terminal|
        finished = create(:order, terminal, customer: customer, merchant: merchant)

        expect(described_class.new(customer, finished).track?).to be false
        expect(described_class.new(owner, finished).track?).to be false
        expect(described_class.new(admin, finished).track?).to be false
      end
    end

    it "refuses another customer and a guest" do
      expect(described_class.new(stranger, order).track?).to be false
      expect(described_class.new(nil, order).track?).to be false
    end
  end

  describe "the scopes" do
    # A SCOPE PER ROLE, not one scope with conditionals. `policy_scope(Order)`
    # resolving to the customer's set is what gave the merchant an empty board
    # — the bug this layout prevents.
    let!(:mine) { create(:order, customer: customer, merchant: merchant) }
    let!(:theirs) { create(:order) }
    let!(:assigned) { create(:order, courier: courier) }

    it "gives the customer only the orders they placed" do
      expect(described_class::Scope.new(customer, Order).resolve).to contain_exactly(mine)
    end

    it "gives a guest nothing rather than everything" do
      expect(described_class::Scope.new(nil, Order).resolve).to be_empty
    end

    # Derived from OWNERSHIP, never from a merchant_id in the request — that
    # parameter is how one restaurant reads another's orders.
    it "gives the merchant scope this owner's orders only" do
      expect(described_class::MerchantScope.new(owner, Order).resolve).to contain_exactly(mine)
    end

    it "gives the merchant scope nothing to somebody without the role" do
      expect(described_class::MerchantScope.new(customer, Order).resolve).to be_empty
    end

    it "gives the courier scope only their assigned jobs" do
      expect(described_class::CourierScope.new(courier, Order).resolve).to contain_exactly(assigned)
    end

    it "gives the courier scope nothing to somebody without the role" do
      expect(described_class::CourierScope.new(customer, Order).resolve).to be_empty
    end

    it "gives admin everything, because the console exists to fix what automation got wrong" do
      expect(described_class::AdminScope.new(admin, Order).resolve)
        .to include(mine, theirs, assigned)
    end

    it "gives the admin scope nothing to a non-admin" do
      expect(described_class::AdminScope.new(customer, Order).resolve).to be_empty
    end
  end
end
