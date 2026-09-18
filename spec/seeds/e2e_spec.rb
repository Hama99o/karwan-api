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

  # ── THE BOARD BRANCHES ON FOUR STATES ────────────────────────────────────
  #
  # The flow failed on `تیار دی` — the action for a `preparing` order — and no
  # fixture produced one. Asserting all four LIVE states rather than the one
  # that was missing, because the same gap hid a second problem: two seeded
  # orders rendered identically while one had a courier and one did not. A
  # fixture covering every state a screen branches on is the seed equivalent of
  # asserting a whole key set.
  describe "the merchant board's states" do
    let(:merchant) { Merchant.find_by!(phone: "+93700000804") }

    it "seeds every live state the board renders" do
      states = merchant.orders.live.pluck(:status).uniq

      expect(states).to include("placed", "accepted", "preparing", "ready"),
                        "the board branches on a state no fixture produces: #{%w[placed accepted preparing ready] - states}"
    end

    # The rig customer's single live order is this file's premise, and these
    # extra states must not have touched it.
    it "leaves the rig customer with exactly one live order" do
      expect(customer.orders.live.count).to eq(1)
    end
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

    # ── THE TOTAL IS AWKWARD ON PURPOSE, AND THIS IS THE GATE ─────────────
    #
    # `Monetary.change_advice` returns nil for any multiple of 100, so a round
    # total means the "bring change for X" line does not render — correctly.
    # The fixture was exactly 500, which made that line **unreachable on a
    # device**: `customer_order_status.yaml` asserted it, could never pass, and
    # the assertion had to be deleted rather than corrected.
    #
    # So the fixture is 505 and this asserts WHY, because the next person to
    # tidy it to a round number would silently remove a feature's only device
    # coverage and nothing else would notice.
    it "has a total the change note can act on, which a round number would not" do
      expect(order.customer_total % 100).not_to eq(0)
      expect(Monetary.change_advice(order.customer_total)).to eq(1000)
    end

    # Model A: the courier advances the items total minus our commission and
    # collects the customer total. Asserted so the awkward number above cannot
    # be changed into an inconsistent set.
    it "keeps Model A's arithmetic consistent" do
      expect(order.merchant_payout).to eq(order.items_total - order.commission)
      expect(order.customer_total).to eq(order.items_total + order.delivery_fee)
    end

    # ── §6: THE COURIER'S NUMBER, AND WHY THIS IS THE GATE THAT MATTERS ────
    #
    # `AFGHAN_UX.md` §6: once there is a courier, HIS number replaces support on
    # the customer's status screen, so the customer — in the doc's own words,
    # *"especially a woman expecting a stranger at the door"* — can reach him
    # first. **That is the one requirement in this app whose failure has a
    # consequence outside the app**, and it had never been exercised anywhere:
    # `Customers::OrderSerializer`'s `courier` field returns nil unless
    # `order.courier` is set, and no fixture set it for this customer.
    #
    # `ready` WITH a courier is not a contrivance — it is what the domain does.
    # `offers_controller#accept` runs `job.update!(courier: current_user)` and
    # touches no status, so this is the normal state between dispatch and the
    # door.
    it "has a courier, so the customer can ring the person coming to the door" do
      expect(order.courier).to be_present
      expect(order.courier.phone).to eq("+93700000803")
      # A phone the app can actually dial. A courier row with no number is the
      # same silence as no courier at all.
      expect(order.courier.phone).to match(/\A\+93\d{9}\z/)
    end

    # The serializer is what the SCREEN reads, so assert through it rather than
    # off the model — the field is inside `view :detailed` and a `list` render
    # does not carry it, which is exactly the kind of gap a model assertion
    # would miss.
    it "serialises the courier to the customer, first name and number" do
      rendered = Customers::OrderSerializer.render_as_hash(order, view: :detailed)

      expect(rendered[:courier]).to be_present
      expect(rendered[:courier][:phone]).to eq("+93700000803")
      # FIRST NAME ONLY — the customer needs to know who is knocking, not who
      # the courier is. The serializer's own comment says so.
      expect(rendered[:courier][:name]).to eq("QA")
    end

    # ── THE PREMISE IS UNCHANGED, AND THAT WAS THE POINT ───────────────────
    #
    # The alternative was a SECOND live order in `picked_up`, which would have
    # broken the one-live-order premise — and the status screen renders the
    # NEWEST live order, so a second would silently move every assertion about
    # this one onto it. I did exactly that with `KQA00003` earlier and this file
    # caught it. Attaching the courier changes one field and keeps the count.
    it "still leaves the rig customer exactly ONE live order" do
      expect(customer.orders.reject(&:terminal?).count).to eq(1)
      expect(order.status).to eq("ready")
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

      # `all` is vacuously true on an empty list. The sibling example above
      # asserts there are at least two — but that is a DIFFERENT example, and a
      # seed change that stopped delivering orders would turn this one green
      # while turning that one red, which reads as one failure rather than two.
      expect(delivered).not_to be_empty, "no delivered orders — both assertions below would be vacuous"
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

      # Seeded orders with no LINES would satisfy "every past line has a
      # pointer" by having no past lines — and the re-order step this exists to
      # protect would still fail on the device.
      expect(pointers).not_to be_empty, "no order lines at all — the assertion below would be vacuous"
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

    # Keyed on the PIN rather than created blind: this file is re-loadable by
    # design and the rig re-seeds between runs, so a bare `create!` would grow
    # the list by three every time and the flow would act on row 1 of 30.
    it "does not add three more when the seed runs again" do
      expect { load Rails.root.join("db/seeds/e2e.rb") }
        .not_to change { customer.reload.addresses.count }
    end

    # ── THE CASE THAT CAUGHT A REAL DEFECT IN THIS SEED ────────────────────
    #
    # The first version keyed on the LABEL. The Profile flow renames a place,
    # so a run left `کور` as `کور نوی`, the next re-seed found no `کور` and
    # made a fourth row, and the run after that asserted against five. Measured
    # against the live API before this was written: 3 → 5 in two re-seeds.
    #
    # Keying on the pin makes a rename SELF-HEALING, which is the property the
    # rig needs — and it is also the right model, because in this product the
    # pin IS the identity of a place and the label is only its human name.
    it "restores a renamed label instead of adding a fourth row" do
      home = customer.addresses.find_by!(is_default: true)
      home.update!(label: "کور نوی")

      expect { load Rails.root.join("db/seeds/e2e.rb") }
        .not_to change { customer.reload.addresses.count }
      expect(home.reload.label).to eq("کور")
    end

    # The flow also CREATES places (the cart's path) and soft-deletes them,
    # which leaves the row in the table. So the seed reconciles rather than
    # only adding — otherwise the fixed set this file promises is only fixed
    # until the first run.
    it "removes a place the rig left behind, so the set stays exactly three" do
      customer.addresses.create!(label: "leftover", latitude: 34.99, longitude: 69.99)

      expect { load Rails.root.join("db/seeds/e2e.rb") }
        .to change { customer.reload.addresses.count }.from(4).to(3)
    end

    # And a demoted default is restored too: the flow taps "make this the usual
    # one" on another row, which the server demotes this one for.
    it "restores the default after the flow has moved it" do
      customer.addresses.find_by!(label: "د مور کور").update!(is_default: true)

      load Rails.root.join("db/seeds/e2e.rb")

      expect(customer.reload.addresses.find_by(is_default: true).label).to eq("کور")
    end
  end
  # ── THE OFFER AND THE LEDGER, WHICH EXIST TO STOP TWO EMPTY FIXTURES ─────
  #
  # `karwan-mobile`'s contract suite had `{"offer": null}` and zero ledger rows,
  # so the offer card's money and an entry's shape had never met a parser. These
  # assert the fixture is POPULATED, because an empty one passes every contract
  # test while proving nothing — `docs/TESTING.md`'s empty-subject shape.
  describe "the courier's pending offer" do
    let(:courier) { User.find_by(phone: "+93700000803") }
    let(:offer)   { Offer.pending.find_by(courier: courier) }

    it "is PENDING, not merely present — an expired offer serialises as nothing" do
      expect(offer).to be_present
      expect(offer.status).to eq("offered")
      expect(offer.expires_at).to be > Time.current
    end

    # The rig's own customer must keep exactly ONE live order: that is what
    # makes the status screen, the merchant board and the map point at the same
    # thing. The first version of this fixture put the offer's order on that
    # account and gave it two, which the list-ordering example caught.
    it "belongs to a DIFFERENT customer than the rig's own" do
      expect(offer.offerable.customer.phone).to eq("+93700000805")
      expect(customer.orders.where(status: :ready).count).to eq(1)
    end

    it "has the money a courier decides on, so the offer card is not blank" do
      job = offer.offerable
      expect(job.items_total).to be > 0
      expect(job.courier_fee).to be > 0
      expect(job.merchant_payout).to eq(job.items_total - job.commission)
    end
  end

  describe "the courier's wallet ledger" do
    let(:wallet) { User.find_by(phone: "+93700000803").courier_wallet }

    it "has more than one KIND, so a parser meets more than a top-up" do
      kinds = wallet.wallet_entries.pluck(:kind).uniq
      expect(kinds.size).to be > 1
      expect(kinds).to include("top_up", "commission")
    end

    # A balance can be recomputed from entries; entries can never be
    # reconstructed from a balance (CLAUDE.md, one-way door 4). So the running
    # total has to be consistent or the fixture teaches a wrong ledger.
    it "keeps balance_after consistent with the running total" do
      running = 0
      wallet.wallet_entries.chronological.each do |entry|
        running += entry.amount
        expect(entry.balance_after).to eq(running)
      end
      expect(wallet.balance).to eq(running)
    end
  end
end
