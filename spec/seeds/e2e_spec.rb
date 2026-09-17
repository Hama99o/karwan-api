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

  # ── CAN THE RIG ACTUALLY GET IN? ─────────────────────────────────────────
  #
  # Asked of the SIGN-IN SERVICE rather than of the column, because "a hash is
  # present" is not the claim — the claim is that typing these values into the
  # two fields on the login screen produces a session.
  #
  # This exists because the switch from a code to a password made every seeded
  # account unreachable in one commit. `POST /auth/otp` used to mint a secret on
  # demand, so a seeded user needed none; with a password, an account seeded
  # without one is refused with THE SAME MESSAGE AS A WRONG PASSWORD — by
  # design, so the existence oracle stays shut — and a device run would have
  # reported "the login is broken" with the login working perfectly.
  describe "signing in the way the rig does" do
    def sign_in(identifier)
      Users::PasswordSignInService.new(identifier: identifier, password: "karwan-qa-password").call
    end

    it "signs each account in with its PHONE and the seeded password" do
      [ customer, owner, courier ].each do |user|
        _signed_in, token, _session = sign_in(user.phone)
        expect(token).to be_present
      end
    end

    # The email branch, which a rig typing only phone numbers would never
    # exercise — and it is the branch a Play-Store reviewer with a Google
    # account will use first.
    it "signs each account in with its EMAIL too" do
      [ customer, owner, courier ].each do |user|
        expect(user.email).to be_present
        _signed_in, token, _session = sign_in(user.email)
        expect(token).to be_present
      end
    end

    # The form a person types on a phone keypad. Normalised on the way in, so
    # it resolves to the same account.
    it "signs in with the LOCAL form of the number" do
      _signed_in, token, _session = sign_in(customer.phone.sub("+93", "0"))

      expect(token).to be_present
    end

    it "refuses the wrong password, so the fixture is not a back door" do
      expect { Users::PasswordSignInService.new(identifier: customer.phone, password: "not it").call }
        .to raise_error(Users::PasswordSignInService::InvalidCredentials)
    end
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

  it "has an active, open merchant with something to sell" do
    merchant = Merchant.find_by(phone: "+93700000804")

    # OWNED BY THE ACCOUNT THE RIG USES, which changed deliberately: the board
    # resolves from `owner_id`, and owned by a different account it 403'd
    # `no_merchant` for three runs while the role was right all along. See "the
    # account the rig signs in as" below.
    expect(merchant.owner).to eq(customer)
    # `+93700000802` stays the business CONTACT, which is what these columns
    # are for — and stops holding `merchant_owner`, correctly, since it owns
    # nothing.
    expect(merchant.owner_phone).to eq(owner.phone)
    expect(owner.role?(:merchant_owner)).to be false
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
  # ── ORDER HISTORY NEEDS PAST ORDERS, and this is the fourth time ──────────
  #
  # The rig had ONE order, live, so the customer's history was empty — and an
  # empty history renders nothing, which on a device looks exactly like a screen
  # that does not work. Three seed gaps of this shape have already cost three
  # runs.
  describe "the orders order history reads" do
    let(:orders) { Order.where(customer: customer).order(placed_at: :desc) }

    # TWO delivered, not one: `fetchActiveOrder` renders the NEWEST order in
    # full at the top whether or not it is live, so a single delivered order
    # would leave nothing to list.
    it "gives the customer at least two DELIVERED orders" do
      expect(orders.select { |order| order.status == "delivered" }.count).to be >= 2
    end

    it "places them in the past, so they are not confused with the live one" do
      delivered = orders.select { |order| order.status == "delivered" }

      expect(delivered).to all(have_attributes(placed_at: be < 1.day.ago))
      expect(delivered.map(&:delivered_at)).to all(be_present)
    end

    # ── THE LIVE ORDER MUST SORT FIRST, and it did not ─────────────────────
    #
    # `/customer/orders` sorts by `newest_first` = `created_at: :desc`, and the
    # app takes `items[0]` as the order to show at the top. The delivered
    # fixtures were inserted NOW with a past `placed_at`, so by `created_at`
    # a nine-day-old delivered order was the newest thing the customer had —
    # and on a device it appeared at the top of the Orders tab with "pay 500 in
    # cash" above it. An order already paid and delivered, presented as live.
    #
    # Asserted on the SORT THE APP ACTUALLY USES rather than on `placed_at`,
    # because that is the one that decides what the customer sees.
    it "puts the LIVE order first in the sort the app reads" do
      first = Order.where(customer: customer).order(created_at: :desc).first

      expect(first.code).to eq("KQA00001")
      expect(first.terminal?).to be(false)
    end

    it "keeps created_at consistent with placed_at, as a real order would" do
      Order.where(customer: customer).each do |order|
        # Within a day: a real order is created when it is placed, and a fixture
        # that breaks that equivalence breaks the sort above.
        expect((order.created_at - order.placed_at).abs).to be < 1.day
      end
    end

    # RE-ORDERABLE, which is the half a status test would miss. "Order this
    # again" resolves `catalog_item_id` against the live menu; a delivered
    # fixture without one is unre-orderable, and the rig's re-order step would
    # fail for a reason that is not the app's.
    it "gives every past line a catalog pointer, so it can be re-ordered" do
      pointers = orders.flat_map { |order| order.order_items.map(&:catalog_item_id) }

      expect(pointers).to all(be_present)
    end

    # And the pointer has to lead somewhere still on the menu, or every
    # re-order resolves to "delisted" and the flow proves the opposite of what
    # it is for.
    it "points at items that are still on the merchant's live menu" do
      orders.flat_map(&:order_items).each do |line|
        expect(line.catalog_item).to be_present
        expect(line.catalog_item.is_available).to be(true)
      end
    end
  end

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

  # ── ONE ACCOUNT, THREE WORKING ROLES ───────────────────────────────────────
  #
  # Every flow signs in as `+93700000801` and switches role from Profile. So
  # holding the roles is not enough — the merchant board resolves from
  # `merchants.owner_id` and the courier screens from an approved profile and a
  # wallet. Three runs were spent discovering that in two different ways:
  #
  #   · the board 403'd `no_merchant`, because QA Kabab House was owned by a
  #     DIFFERENT account. The role was right and the ownership did not match.
  #   · `/courier/job` returned `{"job":null}`, so `job-primary-action` never
  #     rendered and the courier's 64dp is STILL unmeasured on a device.
  #
  # Both are one seed line each, and both cost a whole run.
  describe "the account the rig signs in as" do
    it "holds all three roles" do
      expect(customer.user_roles.map(&:role).sort).to eq(%w[courier customer merchant_owner])
    end

    it "OWNS the merchant, so the board resolves rather than 403ing" do
      expect(Merchant.kept.find_by(owner_id: customer.id)&.name).to eq("QA Kabab House")
    end

    it "is an approved courier with a funded wallet, so the courier screens open" do
      expect(customer.courier_profile).to be_verification_approved
      expect(customer.courier_profile.is_available).to be true
      expect(customer.courier_wallet.balance).to be_positive
    end

    # THE THING THREE RUNS COULD NOT MEASURE.
    it "is carrying a live job, so the courier's primary action renders" do
      job = Order.live.for_courier(customer).first

      expect(job).to be_present
      expect(job.status).to eq("picked_up")
    end

    # `picked_up` is chosen so the step list has a completed step behind it and
    # a money step in front — and so "I am here" is on screen, since the
    # current step is the one at the customer's gate.
    it "is on the step where both the primary action and 'I am here' show" do
      job = Order.live.for_courier(customer).first
      steps = Couriers::JobSteps.new(job).call

      expect(steps.find { |step| step[:current] }[:key]).to eq("go_to_customer")
      expect(steps.find { |step| step[:status_after].present? && !step[:completed] }[:key])
        .to eq("collect_and_deliver")
    end

    # A courier delivering to himself is a state the app permits and nobody
    # should be looking at while measuring a screen.
    it "is not delivering to itself" do
      job = Order.live.for_courier(customer).first

      expect(job.customer_id).not_to eq(customer.id)
    end

    # One live job per courier is enforced by `Dispatch::Eligibility`; a seed
    # that created two would be seeding a state the app refuses.
    it "carries exactly one" do
      expect(Order.live.for_courier(customer).count).to eq(1)
    end
  end

  # ── THE PHOTOS, BECAUSE AN EMPTY CARD IS A DIFFERENT SCREEN ────────────────
  #
  # Hamma9900 saw the app live and every merchant card was an empty grey box
  # taking 60% of its height. Nothing was broken: no seed attached a photo.
  # The QA rig asserts against these cards, so a photo-led screen with no
  # photos is not the screen being tested.
  describe "the photos" do
    let(:merchant) { Merchant.find_by(phone: "+93700000804") }

    it "gives the QA merchant a storefront photo and a logo" do
      expect(merchant.storefront_photo).to be_attached
      expect(merchant.logo).to be_attached
    end

    it "gives the QA dish a photo" do
      item = merchant.catalog_items.find_by(name: "QA Chicken Kabab")

      expect(item.photo).to be_attached
    end

    # THE URL A PHONE ACTUALLY FETCHES. A relative path renders as nothing in a
    # native image view, and would look identical to the empty box it replaced
    # — so the seed and the absolute-URL fix are asserted together.
    it "serves them as absolute urls" do
      rendered = Customers::MerchantSerializer.render_as_hash(
        merchant, view: :detailed, options: { locale: "fa", from: nil }
      )

      expect(rendered[:storefront_photo_url]).to match(%r{\Ahttps?://})
    end

    # Re-running a seed must not pile up blobs: seeds run on every deploy.
    it "does not attach a second copy when the seed runs again" do
      expect { load Rails.root.join("db/seeds/e2e.rb") }
        .not_to change { merchant.reload.storefront_photo_attachment.id }
    end
  end
  # ── THE SAVED PLACES THE PROFILE FLOW ACTS ON ────────────────────────────
  #
  # Three rows, three different cases, and the flow taps rename / remove /
  # make-default on them. Asserted here because an empty list makes the flow
  # pass by asserting nothing — the "empty subject" shape in
  # `docs/TESTING.md`'s four shapes of a lying instrument.
  describe "the customer's saved places" do
    it "seeds three, one of them the default" do
      expect(customer.addresses.count).to eq(3)
      expect(customer.addresses.where(is_default: true).count).to eq(1)
      expect(customer.addresses.find_by(is_default: true).label).to eq("کور")
    end

    # The case the whole feature exists for: a place saved with SOMEBODY
    # ELSE'S number, which is what the courier rings.
    it "gives one of them a different phone from the account holder's" do
      mothers = customer.addresses.find_by(label: "د مور کور")

      expect(mothers.phone).to eq("+93700000901")
      expect(mothers.phone).not_to eq(customer.phone)
    end

    # Without this row the "a courier may not find this from the pin alone"
    # warning is unreachable on a device, so the branch would never be seen.
    it "leaves one a bare pin, so the not-navigable warning has a subject" do
      office = customer.addresses.find_by(label: "دفتر")

      expect(office.landmark_note).to be_nil
      expect(office).not_to be_navigable
    end

    # Keyed on the label rather than created blind: this file is re-loadable by
    # design and the rig re-seeds between runs, so a bare `create!` would grow
    # the list by three every time and the flow would act on row 1 of 30.
    it "does not add three more when the seed runs again" do
      expect { load Rails.root.join("db/seeds/e2e.rb") }
        .not_to change { customer.reload.addresses.count }
    end
  end
end
