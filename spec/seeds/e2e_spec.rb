require "rails_helper"

# THE E2E SEED IS A CONTRACT, and `qa/lib/common.sh` holds the other half.
#
# The QA rig signs in with these exact phone numbers and asserts against these
# exact records. A cosmetic change here — a renamed merchant, a phone that
# moved, a courier left unapproved — breaks a device run that will be blamed on
# the app, at the end of a five-minute build, by someone who did not make the
# change.
#
# So the contract is asserted here, where it fails in two seconds instead.
RSpec.describe "db/seeds/e2e.rb" do
  # `seed_section` is defined by db/seeds.rb, which this does not load — it
  # loads the two files it needs directly, so a broken sample.rb cannot fail
  # this spec for an unrelated reason. The shim must CALL the block; a first
  # version silently swallowed it and every example failed against an empty
  # database, which read as "the seed is broken" rather than "the harness is".
  #
  # `before`, NOT `before(:all)` — and that cost a real failure to learn.
  # With `use_transactional_fixtures`, a `before(:all)` runs OUTSIDE the
  # per-example transaction, so its rows are COMMITTED and live for the rest of
  # the suite. "QA Kabab House" then leaked into a cross-script search spec
  # three directories away and failed an assertion about multi-word narrowing.
  #
  # A spec that makes OTHER specs unreliable is worse than no spec, and it
  # fails somewhere that gives no hint where to look. Per-example is a couple
  # of seconds slower and cannot do that.
  before do
    Object.send(:define_method, :seed_section) { |_title, &block| block.call }
    load Rails.root.join("db/seeds/reference.rb")
    load Rails.root.join("db/seeds/e2e.rb")
  end

  # The numbers the rig types. If one of these changes, change qa/lib/common.sh
  # in the same commit.
  let(:customer) { User.find_by(phone: "+93700000801") }
  let(:owner) { User.find_by(phone: "+93700000802") }
  let(:courier) { User.find_by(phone: "+93700000803") }

  it "creates the three accounts the rig signs in as" do
    expect(customer).to be_present
    expect(owner).to be_present
    expect(courier).to be_present
  end

  # F-18: there is no way back from merchant or courier to customer. A flow
  # cannot even reach that problem without one account holding all three roles.
  it "gives the customer all three roles, so the role switch has somewhere to go" do
    expect(customer.user_roles.pluck(:role)).to include("customer", "merchant_owner", "courier")
  end

  # `Couriers::BaseController` refuses an unapproved courier with `not_approved`,
  # which leaves the courier screens exactly as empty as having no account.
  it "leaves the courier APPROVED, with the role and a funded wallet" do
    expect(courier.courier_profile).to be_verification_approved
    expect(courier.role?(:courier)).to be true
    expect(courier.courier_wallet).to be_present
    expect(courier.courier_wallet.balance).to be > 0
  end

  it "gives the merchant owner an active, open merchant with something to sell" do
    merchant = Merchant.find_by(phone: "+93700000804")

    expect(merchant.owner).to eq(owner)
    expect(merchant).to be_status_active
    expect(merchant.is_open).to be true
    expect(merchant.catalog_items.kept).to be_present
  end

  describe "the one live order" do
    let(:order) { Order.find_by(code: "KQA00001") }

    # `ready` is the state where the most screens have something at once: the
    # merchant board has a card, the customer's status screen has a timeline,
    # and the map has two points to draw.
    it "is live, and in the state that lights up the most screens" do
      expect(order).to be_present
      expect(order.status).to eq("ready")
      expect(order).not_to be_terminal
    end

    # F-05 has been open across two runs: MapLibre has never been mounted,
    # because the map gates on an active order.
    it "has both ends, so the MAP has something to draw" do
      expect(order.delivery_latitude).to be_present
      expect(order.merchant.latitude).to be_present
    end

    # Without the transition rows the customer's five steps render as five
    # pending ones for an order that is nearly there.
    it "carries the timeline the customer's steps are stamped from" do
      expect(order.transitions.pluck(:to_status)).to include("accepted", "preparing", "ready")
    end

    it "has a line item, so the merchant's card is not empty" do
      expect(order.order_items).to be_present
    end
  end

  # F-20: the app draws the support bar only when there IS a number, so without
  # this row the rig's highest-value RTL assertion has nothing to assert.
  it "sets a support number, which /public/app_config serves to every role" do
    expect(Setting.fetch("support_phone")).to be_present
  end

  # Re-run after a deploy, re-run by a developer, re-run by the rig's own seed
  # step — a seed that duplicates on a second run is a seed nobody dares run.
  it "is idempotent — a second run changes nothing" do
    before_counts = [ User.count, Order.count, Merchant.count, CourierProfile.count ]

    load Rails.root.join("db/seeds/e2e.rb")

    expect([ User.count, Order.count, Merchant.count, CourierProfile.count ]).to eq(before_counts)
  end
end
