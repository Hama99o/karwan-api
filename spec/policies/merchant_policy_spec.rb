require "rails_helper"

RSpec.describe MerchantPolicy do
  let(:owner) { create(:user, :merchant_owner) }
  let(:merchant) { create(:merchant, owner: owner) }
  let(:admin) { create(:user, :admin) }
  let(:customer) { create(:user, :customer) }

  describe "browsing" do
    # Open, including to guests. Correction 10: let them see a merchant before
    # asking for anything.
    #
    # `#show?` AND THE SCOPE, and deliberately not `#index?`, which used to be
    # asserted here and has been deleted. Pundit never reached it: every index
    # action in this API is gated by `policy_scope` under `verify_policy_scoped`,
    # and `verify_authorized` is skipped for index precisely so that is the rule.
    # Asserting a predicate nothing consults is a green check on an unused gate.
    it "is allowed for everyone, including a guest with no user at all" do
      [ nil, customer, owner, admin ].each do |actor|
        expect(described_class.new(actor, merchant).show?).to be true
      end
    end

    # What actually decides the listing, for the same four actors.
    it "lists live approved merchants for everyone, guest included" do
      [ nil, customer, owner, admin ].each do |actor|
        expect(described_class::Scope.new(actor, Merchant.all).resolve).to include(merchant)
      end
    end
  end

  describe "#update?" do
    it "allows the merchant's own owner" do
      expect(described_class.new(owner, merchant).update?).to be true
    end

    it "allows an admin" do
      expect(described_class.new(admin, merchant).update?).to be true
    end

    # THE edu-safi LESSON, as a spec. Holding the merchant_owner role is
    # tenancy; owning THIS merchant is permission. A shop owner editing a rival
    # is the bug this prevents, and it is the one that shipped five times.
    it "refuses a merchant owner who does not own THIS merchant" do
      other_owner = create(:user, :merchant_owner)

      expect(described_class.new(other_owner, merchant).update?).to be false
    end

    it "refuses a customer" do
      expect(described_class.new(customer, merchant).update?).to be false
    end

    it "refuses a guest" do
      expect(described_class.new(nil, merchant).update?).to be false
    end

    # An unowned merchant (admin onboarded it, the owner has no account yet)
    # must not be editable by anyone holding the role.
    it "refuses everyone but admin when the merchant has no owner" do
      unowned = create(:merchant, owner: nil)

      expect(described_class.new(owner, unowned).update?).to be false
      expect(described_class.new(admin, unowned).update?).to be true
    end
  end

  describe "#toggle_open? and #manage_catalog?" do
    # Its own predicate rather than folded into update?, because admin must be
    # able to close a shop on its behalf — the single most important control in
    # the system — without that implying it can rewrite the menu.
    it "allows the owner and admin, refuses everyone else" do
      expect(described_class.new(owner, merchant).toggle_open?).to be true
      expect(described_class.new(admin, merchant).toggle_open?).to be true
      expect(described_class.new(customer, merchant).toggle_open?).to be false
      expect(described_class.new(nil, merchant).manage_catalog?).to be false
    end
  end

  describe "#create? and #destroy?" do
    # Merchants are not self-serve in v0 — admin onboards them.
    it "is admin only" do
      expect(described_class.new(admin, merchant).create?).to be true
      expect(described_class.new(owner, merchant).create?).to be false
      expect(described_class.new(admin, merchant).destroy?).to be true
      expect(described_class.new(owner, merchant).destroy?).to be false
    end
  end

  describe "Scope" do
    it "shows only live, approved merchants" do
      visible = create(:merchant)
      create(:merchant, :pending)
      create(:merchant, :suspended)
      create(:merchant).discard!

      resolved = described_class::Scope.new(customer, Merchant).resolve

      expect(resolved).to contain_exactly(visible, merchant)
      expect(resolved).to include(visible)
    end

    it "resolves the same for a guest as for a customer" do
      create(:merchant, :pending)

      guest = described_class::Scope.new(nil, Merchant).resolve
      signed_in = described_class::Scope.new(customer, Merchant).resolve

      expect(guest.pluck(:id).sort).to eq(signed_in.pluck(:id).sort)
    end
  end
end
