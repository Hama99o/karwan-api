# E2E FIXTURES — the accounts and the one live order the QA rig drives.
#
# ── Why this file exists ──────────────────────────────────────────────────
# `qa/UI_FINDINGS.md` F-15: every role-scoped endpoint answered 401, so the
# only surface the app could reach was the public merchant list. The map had
# still never been mounted, the courier's 64dp action had still never been
# measured on a device, and the merchant board had no data — four findings, one
# cause. A device run cannot authenticate without accounts it can predict.
#
# ── DISTINCT FROM sample.rb, deliberately ─────────────────────────────────
# `sample.rb` makes a believable world with faked names and sequential phones;
# it is for a human clicking around. This file makes a SMALL, FIXED, NAMED set
# that automated flows assert against by value — change a number here and a
# flow breaks, which is the point. Two files because mixing them means a
# cosmetic tweak to the demo world silently breaks the suite.
#
# Development and test only: `db/seeds.rb` refuses sample data in production and
# this is loaded the same way.
#
# ── The rig signs in like a person does ───────────────────────────────────
# There is no back door and no injected token: a flow types an identifier and a
# password into the same two fields a real user does. That is what keeps
# correction 17 true — no mocks in the app, including for the rig.
#
# It used to read the OTP out of the `POST /auth/otp` response, because identity
# was a phone plus a code. Hamma9900 replaced that with a password
# (`docs/IDENTITY_AND_ROLES.md` §1), so THE RIG'S SIGN-IN STEP CHANGED SHAPE:
# two fields typed, no response to read in between. The code path is retained
# and switched off behind `otp_sign_in_enabled`, so a flow still driving it gets
# `otp_disabled` rather than a code — which is a clear failure rather than a
# confusing one.
#
# THE PHONES AND THE PASSWORD ARE THE CONTRACT. `qa/lib/common.sh` in
# karwan-mobile holds the same values and has to be changed with this file.

# ── WHAT THIS SEED DOES NOT OWN, AND WHO DOES ─────────────────────────────
#
# **A precondition belongs to whoever CAN set it: the dependent flow first, the
# producing flow never, and the rig when neither has the reach. An assumption
# written as a comment is never allowed.** Three separate problems in this
# file's vicinity on 2026-09-18 were all this rule being broken, and each cost a
# debugging session on a screen that was working correctly.
#
#   * A board run leaves the shop **CLOSED** — `merchant_board_no_tabs` closes
#     it in section 4 and cancels the reopen. The damage lands off its own
#     screen: the customer's Home then shows a dimmed card, and the next person
#     to open Home debugs a restaurant that is fine. **The rig reopens it** in
#     `require_rig` via `qa.sh shop-open`, so the shop's open state is a rig
#     BASELINE like the seeded addresses — not any flow's precondition, because
#     a Maestro flow cannot call the API to set one.
#   * The board renders four live states and this seed produced two, so a flow
#     failed on an action label for a state no fixture could reach. Fixed by
#     seeding every state the screen branches on.
#   * A photo step lived inside a section guarded by `next if X.any?`, so it was
#     dead on every database that already had X — see `db/seeds/stress.rb`.
#
# **The consequence for anyone writing a spec here: never read `is_open` off the
# dev database.** Use a factory. That value is a rig baseline and a board run
# moves it; a spec that reads it is asserting on somebody else's fixture.
#
# `||=` rather than a bare assignment: this file is re-loadable by design (the
# rig re-seeds between runs, and a spec loads it twice to prove it is
# idempotent), and a bare constant assignment warns on every reload.
E2E ||= {
  customer: "+93700000801",
  merchant_owner: "+93700000802",
  courier: "+93700000803",
  # A SECOND customer, whose only job is to own the order the courier is
  # OFFERED. It exists so the rig's own customer keeps exactly ONE live order —
  # this file's premise, and what makes the status screen, the merchant board
  # and the map all point at the same thing. A courier is offered any
  # customer's order and pre-accept does not see whose it is, so tying the
  # offer to the rig's account was a coincidence pretending to be a
  # relationship.
  offer_customer: "+93700000805"
}.freeze

# ONE PASSWORD FOR EVERY FIXTURE ACCOUNT, and deliberately an obvious one: it
# is typed by hand during a device run and it must never exist anywhere real.
# `db/seeds.rb` refuses this whole tree in production, which is what makes a
# shared known password safe here and nowhere else.
E2E_PASSWORD ||= "karwan-qa-password"

# Every fixture account is also given an EMAIL, because the sign-in field takes
# either and a rig that only ever types a phone number would leave the email
# branch unexercised on a device — the branch most likely to be wrong, since it
# is the one a Play-Store reviewer with a Google account will use.
def e2e_user!(phone, name:, role:, locale: "ps", email: nil)
  user = User.find_or_initialize_by(phone: phone)
  user.email = email if email.present?
  user.password = E2E_PASSWORD
  # ── `phone_verified_at` IS DELIBERATELY NOT SET ANY MORE ─────────────────
  #
  # It used to be stamped here, and after the switch to passwords that became a
  # state THE APP CANNOT PRODUCE: the only thing that ever set it was the OTP
  # sign-in, which is switched off, and `Users::RegistrationService` leaves it
  # nil because there is no verification step. A fixture describing an
  # impossible world is the exact failure `docs/TESTING.md` records — and it
  # had already been found once in this very file, on `merchant_owner`.
  #
  # Nothing branches on it (checked: one serializer field and one console
  # column, no policy and no client), so the only visible effect is that the
  # ops console shows QA fixtures the same way it shows real users. Which is
  # the point.
  user.update!(name: name, locale: locale, last_active_role: role)
  user.user_roles.find_or_create_by!(role: role)
  user
end

seed_section "e2e accounts" do
  customer = e2e_user!(E2E[:customer], name: "QA Customer", role: :customer,
                       email: "qa.customer@karwan.af")
  # THE BUSINESS CONTACT, and a plain customer.
  #
  # It used to be seeded with `merchant_owner` — while owning nothing, because
  # the merchant now belongs to the account the rig signs in as. That is a
  # state the APP CANNOT PRODUCE: nothing grants `merchant_owner` except
  # `Merchant#sync_owner_role`, which grants it to an owner. A fixture
  # describing an impossible world is the failure mode `docs/TESTING.md`
  # records, and it was in the seed the QA rig trusts.
  #
  # It is the recipient of the courier's live job below, which is the other
  # thing it is for: a courier must not be delivering to himself while somebody
  # measures that screen.
  owner = e2e_user!(E2E[:merchant_owner], name: "QA Merchant", role: :customer,
                    email: "qa.merchant@karwan.af")
  courier = e2e_user!(E2E[:courier], name: "QA Courier", role: :courier,
                      email: "qa.courier@karwan.af")

  # The customer also HOLDS the other two roles, so the role switch has
  # somewhere to go on one account. F-18 found there is no way back from
  # merchant or courier to customer; a flow cannot even reach the problem
  # without an account that holds all three.
  %i[merchant_owner courier].each { |role| customer.user_roles.find_or_create_by!(role: role) }

  # A merchant the flows name by value.
  #
  # ── OWNED BY THE CUSTOMER ACCOUNT, and that is not a mistake ─────────────
  #
  # Every flow signs in as `+93700000801` and switches role from Profile —
  # that is why this account holds all three roles. But the board resolves
  # from `merchants.owner_id`, so with the merchant owned by
  # `+93700000802` the rig switched to merchant mode and got a **403
  # `no_merchant`**: the role was right and the ownership did not match.
  #
  # Three runs of the merchant board were spent on that. The role and the
  # ownership have to agree on ONE account, because that is the account the rig
  # uses.
  #
  # `+93700000802` stays as the business CONTACT (`owner_name`/`owner_phone`
  # below), which is what those columns are for, and stops holding
  # `merchant_owner` — `Merchant#sync_owner_role` revokes it, correctly: it
  # owns nothing.
  merchant = Merchant.find_or_initialize_by(phone: "+93700000804")
  merchant.assign_attributes(
    name: "QA Kabab House", owner: customer, merchant_kind: MerchantKind.first,
    owner_name: "QA Merchant", owner_phone: E2E[:merchant_owner],
    status: :active, is_open: true, prep_time_minutes: 20,
    latitude: 34.5553, longitude: 69.2075,
    landmark_note: "QA fixture — blue gate", commission_rate: 0.125
  )
  merchant.save!

  # THE QA RIG SEES WHAT A CUSTOMER SEES. A photo-led card with no photo is a
  # different screen from the one being tested, and the flows assert on it —
  # `docs/NOTES.md`: verify at the layer where it lands.
  Attachments::SeedPhoto.attach!(merchant, :logo, "logo_kabab.jpg")
  Attachments::SeedPhoto.attach!(merchant, :storefront_photo, "storefront_kabab.jpg")

  category = merchant.catalog_categories.find_or_initialize_by(name: "QA Kababs")
  category.update!(position: 0)

  item = merchant.catalog_items.find_or_initialize_by(name: "QA Chicken Kabab")
  item.update!(catalog_category: category, price: 400, currency: "AFN", is_available: true)
  Attachments::SeedPhoto.attach!(item, :photo, "kabab.jpg")

  # The COURIER must be approvable and approved, or `Couriers::BaseController`
  # refuses every request with `not_approved` and the courier screens are as
  # empty as they were with no account at all.
  #
  # TWO PROFILES, and for the same reason the merchant is owned by the
  # customer: the rig signs in as ONE account and switches roles, so that
  # account needs a working courier profile of its own. The dedicated courier
  # account keeps one too, for API-level checks that do not go through the app.
  [ courier, customer ].each do |person|
    profile = person.courier_profile || CourierProfile.new(user: person)
    profile.assign_attributes(
      full_name: person == courier ? "QA Courier" : "QA Customer-Courier",
      national_id_number: "1400-QA-000#{person == courier ? 1 : 2}",
      guarantor_name: "QA Guarantor", guarantor_phone: "+93700000805",
      vehicle_type: :motorbike, accepted_job_kinds: %w[delivery ride],
      verification_status: profile.verification_status || :pending,
      # ON SHIFT, because an offline courier sees the availability toggle and
      # nothing else — and the job screen is what three runs have failed to
      # measure.
      is_available: true
    )
    profile.save!
    %i[id_document selfie].each do |document|
      next if profile.public_send(document).attached?

      profile.public_send(document).attach(
        io: Rails.root.join("spec/fixtures/files/photo.png").open,
        filename: "#{document}.png", content_type: "image/png"
      )
    end
  end
  # `approve!` grants the status, the role AND the wallet in one transaction —
  # a courier approved with two of the three cannot work and cannot be told why.
  #
  # The approver is resolved HERE rather than taken from `AdminUser.first`,
  # which was nil whenever this file ran without `sample.rb` — and `approve!`
  # correctly refuses an approval with no approver, so the whole seed died.
  # Reuses the ops account when sample.rb already made it; creates it when not,
  # so this file stands alone.
  approver = AdminUser.find_or_create_by!(email: "ops@karwan.af") do |admin|
    admin.name = "Karwan Operations"
    admin.password = "karwan-dev-password"
    admin.password_confirmation = "karwan-dev-password"
  end
  # ── THE OPENING FLOAT IS A LEDGER ENTRY, NOT A BALANCE ─────────────────────
  #
  # This wrote `update!(balance: 5_000)` directly, and it produced two states the
  # app cannot produce. Both were invisible to the idempotency example below,
  # which compares ROW COUNTS — and a balance drift is an UPDATE.
  #
  #   · +93700000801, the account every flow signs in as, held 5,000 with ZERO
  #     ledger rows on the very first run. A balance nothing explains.
  #   · +93700000803 drifted on a RE-RUN: this line reset it to 5,000 while the
  #     ledger section below, guarded against re-running, left its entries
  #     summing to 2,160.
  #
  # One-way door 4 is the rule it broke, and the ledger section below cites that
  # door by name twelve lines into its own comment. A balance can always be
  # recomputed from entries; entries can never be reconstructed from a balance.
  #
  # `record_entry!` is the single locked entry point (MONEY_AND_SETTLEMENT §10),
  # so it writes the row, the `balance_after` and the balance together and the
  # arithmetic cannot drift from the ledger. Guarded on the wallet being empty,
  # which is what makes a second run change nothing.
  [ courier, customer ].each do |person|
    person.courier_profile.approve!(by: approver) unless person.courier_profile.verification_approved?
    wallet = person.reload.courier_wallet
    next if wallet.nil?

    wallet.update!(credit_line: 500)
    next if wallet.wallet_entries.any?

    wallet.record_entry!(kind: :top_up, amount: 5_000, recorded_by_admin_user: approver,
                         note: "opening float, seeded")
  end
end

# ── THE CUSTOMER'S SAVED PLACES ───────────────────────────────────────────
#
# Seeded because **the rig could not reach this feature at all without them.**
# `addresses` had a table, five endpoints, policies and a serializer, and the
# app rendered the list nowhere but the cart's destination picker — so a
# customer could save a place and never see it again. The Profile screen is now
# its second consumer and the first one that can rename, remove, or choose a
# default, and a flow cannot exercise any of those against an empty list.
#
# THREE, and each one is a different case rather than padding:
#
#   1. `کور` — the DEFAULT. Proves the "· the usual one" marker renders and
#      that `make_default` on another row demotes this one, which is a
#      server-side demotion the client can only be shown by refetching.
#   2. `د مور کور` — a place with SOMEBODY ELSE'S PHONE. This is the case the
#      whole feature exists for (`AFGHAN_UX.md` §7: one person with a
#      smartphone books for a whole family), and the number the courier rings
#      is this one rather than the account holder's.
#   3. `دفتر` — a BARE PIN, no landmark and no voice note, so `navigable?` is
#      false and the "a courier may not find this from the pin alone" warning
#      has something to render on. Without it that branch is unreachable on a
#      device.
#
# Labels are in Pashto on purpose: the rig runs in Pashto, and a Latin label
# would not prove the row renders an Afghan script at all.
seed_section "e2e saved addresses" do
  customer = User.find_by!(phone: E2E[:customer])

  # ── KEYED ON THE PIN, NOT ON THE LABEL, AND THAT WAS A REAL DEFECT ──────
  #
  # The first version of this keyed `find_or_initialize_by(label:)`. **The
  # Profile flow renames a place**, so a run left `کور` as `کور نوی`, the next
  # re-seed found no `کور` and created a fourth row, and the run after that
  # asserted against a five-row list. Measured, not imagined: 3 → 5 in two
  # re-seeds. A flow that degrades the fixture it tests is worse than no flow.
  #
  # The pin is the right key because **in this product the pin IS the identity
  # of a place** — there is no street address, by design (CLAUDE.md, "the
  # address problem") — and the label is the mutable human name for it. So a
  # rename is self-healing: the same pin is found and its label reset.
  # A LOCAL, not a constant. This file is re-loadable by design — the rig
  # re-seeds between runs and a spec loads it twice to prove idempotence — and
  # a constant assigned in here warns `already initialized constant FIXTURES`
  # on every reload. The file's own header says `||=` for exactly that reason;
  # a local needs no such dodge, because nothing outside this block wants it.
  fixtures = [
    { label: "کور", landmark_note: "شین دروازه، دویم پوړ", phone: customer.phone,
      latitude: 34.5400, longitude: 69.1750, is_default: true },
    { label: "د مور کور", landmark_note: "د پارک مخې ته، سره دروازه", phone: "+93700000901",
      latitude: 34.5320, longitude: 69.1680, is_default: false },
    # NO landmark and NO phone: the not-navigable case.
    { label: "دفتر", landmark_note: nil, phone: nil,
      latitude: 34.5460, longitude: 69.1820, is_default: false }
  ].freeze

  kept_ids = fixtures.map do |fixture|
    address = customer.addresses.find_or_initialize_by(
      latitude: fixture[:latitude], longitude: fixture[:longitude]
    )
    address.assign_attributes(fixture)
    address.save!
    address.id
  end

  # ── THIS SEED OWNS THE LIST, so it reconciles rather than only adding ────
  #
  # The flow CREATES places (the cart's path) and DELETES them, and a soft
  # delete leaves the row in the table — so without this, every run would add
  # to a list the specs assert the size of. This file's own header says it
  # makes "a SMALL, FIXED, NAMED set that automated flows assert against by
  # value"; that is only true if the set is exactly this set afterwards.
  #
  # A HARD delete, and only here: this is a fixture file that `db/seeds.rb`
  # refuses to load in production, and an order SNAPSHOTS its delivery address
  # rather than joining to this table (one-way door 1), so removing a fixture
  # row cannot rewrite anybody's history. Verified against the live API — order
  # KQA00011 still reported its own landmark after its address was deleted.
  customer.addresses.where.not(id: kept_ids).destroy_all
end

seed_section "e2e live order" do
  customer = User.find_by!(phone: E2E[:customer])
  merchant = Merchant.find_by!(phone: "+93700000804")
  courier  = User.find_by!(phone: E2E[:courier])
  item = merchant.catalog_items.first

  # ONE live order, in `ready` — the state where the most screens have
  # something to show at once: the merchant board has a card, the customer's
  # status screen has a timeline, and the MAP has two points to draw. F-05 has
  # been open across two runs because MapLibre has never been mounted, and the
  # map gates on an active order.
  order = Order.find_or_initialize_by(code: "KQA00001")
  order.assign_attributes(
    customer: customer, merchant: merchant, status: :ready,
    # ── AN AWKWARD TOTAL ON PURPOSE, SO THE CHANGE NOTE HAS SOMETHING TO SAY ─
    #
    # This was 400 + 100 = **500**, and `Monetary.change_advice` returns nil for
    # any multiple of 100 — correctly, because exact notes exist for it. So the
    # "bring change for X" line, which is a real AFGHAN_UX feature about a
    # courier and a customer settling cash at a gate, **was unreachable on a
    # device**: `customer_order_status.yaml` asserted it, could never pass, and
    # the assertion had to be removed rather than fixed.
    #
    # 405 + 100 = **505**, which is not a multiple of 100, so `change_advice`
    # returns `ceil(505 / 500) * 500 = 1000` and the note renders. One digit of
    # fixture buys a feature its only device coverage.
    #
    # Model A stays consistent: the courier advances `items_total - commission`
    # (405 − 50 = 355) and collects `customer_total` (505).
    items_total: 405, delivery_fee: 100, commission: 50, courier_fee: 100,
    merchant_payout: 355, customer_total: 505, currency: "AFN",
    payment_method: :cash, payment_status: :pending,
    delivery_latitude: 34.5400, delivery_longitude: 69.1750,
    delivery_landmark_note: "QA fixture — second floor, blue gate",
    customer_phone: customer.phone,
    placed_at: 20.minutes.ago, accepted_at: 18.minutes.ago,
    preparing_at: 15.minutes.ago, ready_at: 2.minutes.ago,
    # SET EXPLICITLY, so the sort does not depend on when this row was first
    # inserted. `find_or_initialize_by` keeps the original `created_at` across
    # re-seeds, so this order's position in a `created_at: :desc` list drifted
    # further back every day while the delivered fixtures below stayed a fixed
    # number of days old — and the live order eventually sinks beneath them.
    created_at: 20.minutes.ago
  )
  # ── A COURIER IS ASSIGNED, AND THE STATUS STAYS `ready` ────────────────────
  #
  # This is what the domain actually does: `offers_controller#accept` runs
  # `job.update!(courier: current_user)` and **touches no status** — a courier
  # is attached at accept and the order stays `ready` until pickup. So a
  # `ready` order WITH a courier is not a contrivance, it is the normal state
  # between dispatch and the door.
  #
  # ── WHY THIS MATTERS MORE THAN THE REST OF THIS FILE ──────────────────────
  #
  # `AFGHAN_UX.md` §6: once there is a courier, HIS number replaces support on
  # the customer's status screen, so the customer — in the doc's own words,
  # *"especially a woman expecting a stranger at the door"* — can reach him
  # first. **That is the one requirement in this app where being wrong has a
  # consequence outside the app**, and it had never been seen on a device:
  # `Customers::OrderSerializer`'s `courier` field returns `nil` unless
  # `order.courier` is set, and no fixture ever set it for this customer.
  #
  # ── AND THE ONE-LIVE-ORDER PREMISE IS UNCHANGED, DELIBERATELY ─────────────
  #
  # The alternative was a SECOND live order in `picked_up`. That would have
  # broken this file's premise — one live order for the rig customer, which is
  # what makes the status screen, the merchant board and the map all point at
  # the same thing — and the status screen renders the NEWEST live order, so a
  # second one would silently move every assertion about this one onto it. I
  # did exactly that with `KQA00003` earlier today and the seed spec caught it.
  #
  # Attaching the courier here changes ONE field, keeps the count at one, and
  # keeps `ready` — so the merchant board still has its card, the timeline
  # still has its stamps, and the map still has two points.
  order.courier = courier

  # ── AND HE HAS REACHED THE SHOP ────────────────────────────────────────
  #
  # `courier_arrived_at` is the customer's middle state — *"your courier has
  # reached the restaurant"* — and it was NULL on every seeded order, so the
  # tracking screen could not be designed against it: a field that is always
  # null gets designed around rather than for.
  #
  # It is also a fixture correctness fix. A courier who is assigned to a `ready`
  # order is standing at the counter waiting for it, and the same order reaches
  # `picked_up` during a rig run — a courier who collected an order without ever
  # arriving is a state the domain cannot produce.
  order.courier_arrived_at ||= 2.minutes.ago
  order.save!

  if order.order_items.empty?
    order.order_items.create!(catalog_item: item, name: item.name, unit_price: 400,
                              quantity: 1, options_total: 0, line_total: 400, currency: "AFN")
  end

  # The timeline the customer's five steps are stamped from. Without these the
  # status screen renders five pending steps for an order that is nearly there.
  [ %w[placed accepted], %w[accepted preparing], %w[preparing ready] ].each_with_index do |(from, to), index|
    next if order.transitions.exists?(to_status: to)

    order.transitions.create!(from_status: from, to_status: to, actor: nil,
                              created_at: (18 - (index * 3)).minutes.ago)
  end

  # ── TWO DELIVERED ORDERS, SO ORDER HISTORY HAS SOMETHING TO LIST ──────────
  #
  # The fourth instance of the same seed gap. The rig had ONE order, live, so
  # the customer's history was empty — and `OrderHistory` renders nothing when
  # it is empty, which on a device looks exactly like a screen that does not
  # work. The three before this cost three runs between them.
  #
  # TWO, not one, and that is not padding: `fetchActiveOrder` renders the
  # NEWEST order in full at the top whether or not it is live, so with a single
  # delivered order there would be nothing left to list. Two means one is shown
  # above and one is history.
  #
  # Both carry a REAL `catalog_item`, because "order this again" resolves that
  # pointer against the live menu — a delivered order with no pointer is
  # unre-orderable and would make the rig's re-order step fail for a reason
  # that is not the app's.
  [
    { code: "KQA00010", days_ago: 3 },
    { code: "KQA00011", days_ago: 9 }
  ].each do |fixture|
    past = Order.find_or_initialize_by(code: fixture[:code])
    placed = fixture[:days_ago].days.ago
    past.assign_attributes(
      customer: customer, merchant: merchant, status: :delivered,
      items_total: 400, delivery_fee: 100, commission: 50, courier_fee: 100,
      merchant_payout: 350, customer_total: 500, currency: "AFN",
      payment_method: :cash, payment_status: :collected,
      delivery_latitude: 34.5400, delivery_longitude: 69.1750,
      delivery_landmark_note: "QA fixture — second floor, blue gate",
      customer_phone: customer.phone,
      placed_at: placed, accepted_at: placed + 2.minutes,
      preparing_at: placed + 5.minutes, ready_at: placed + 20.minutes,
      picked_up_at: placed + 25.minutes, delivered_at: placed + 40.minutes,
      # ── `created_at` TOO, AND THAT IS NOT COSMETIC ────────────────────────
      #
      # `/customer/orders` sorts by `newest_first`, which `Dispatchable` defines
      # as `created_at: :desc` — correct and cheap in production, where an order
      # is created at the moment it is placed.
      #
      # A seed breaks that equivalence: these rows are inserted NOW with a
      # `placed_at` in the past, so by `created_at` a nine-day-old delivered
      # order was the NEWEST thing the customer had. On a device that put it at
      # the top of the Orders tab with "pay 500 in cash" above it — an order
      # already paid and delivered, presented as the live one.
      #
      # Fixed here rather than by changing the sort, because the sort is right:
      # `created_at` is never null and is monotonic, and `placed_at` is neither.
      # The fixture was describing a state the app cannot produce — the fifth
      # instance of that pattern in this project, and the first one I wrote.
      created_at: placed
    )
    past.save!

    next unless past.order_items.empty?

    past.order_items.create!(catalog_item: item, name: item.name, unit_price: 400,
                             quantity: 1, options_total: 0, line_total: 400, currency: "AFN")
  end
end

# ── A LIVE JOB, so the courier's screen has something on it ─────────────────
#
# `/courier/job` returned `{"job":null}` for three runs, so
# `job-primary-action` never rendered and **the courier's 64dp primary action
# is still unmeasured on a device** — the single most-repeated open question in
# `qa/UI_FINDINGS.md`. The shift, the wallet and the approval were all seeded;
# the job was not, and without one the courier screen is the availability
# toggle and nothing else.
#
# `picked_up` is chosen deliberately: it is the state where the step list has
# a completed step behind it and a money step in front, the map has both
# points, and "I am here" is on screen. A `ready` job would show the first step
# only.
# ── A PENDING OFFER AND A WALLET LEDGER, BECAUSE TWO FIXTURES WERE EMPTY ──
#
# `karwan-mobile/src/api/__tests__/contract.test.ts` replays the real server's
# bytes through the real parsers, and it found two BLOCKERs that 749 green unit
# tests could not (F-40, F-41). **Two of its fixtures were honestly weak and
# said so in their own test names**: `courier_offer.json` was `{"offer": null}`
# and `courier_wallet_entries.json` had zero rows, so the offer card's money and
# a ledger entry's shape had never been through a parser at all.
#
# The test's header named the fix: "a seed with a live offer, not a softer
# assertion". This is that.
#
# ── HONEST ABOUT THE SUSPICION, WHICH IS NOW LOW ──────────────────────────
#
# A static cross-check of the offer path before writing this found it CLEAN on
# both known classes: every field the client requires is serialised (no F-41),
# and `earnings`, `advance_required`, `total_to_collect` and the pickup
# coordinates all go through `money()` rather than `num()`, so a Rails decimal
# arriving as a string is already handled (no F-40).
#
# It is seeded anyway, because F-40's whole lesson is that **reading a shape is
# not measuring it** — a hand-checked payload agrees with itself exactly as a
# hand-written fixture does. The expected outcome is a green test that proves
# something rather than a red one.
#
# ── AN OFFER FIXTURE IS TIME-LIMITED, UNLIKE EVERY OTHER ROW HERE ─────────
#
# `Offer.pending` is `status_offered.where(expires_at: Time.current..)`, so a
# seeded offer stops being pending when it expires. That is the domain being
# honest — a 60-second dispatch deadline is the point — but it means **the
# capture must happen within the window**, which `qa/CONTRACT_FIXTURES.md`
# now says. Once captured, the fixture file is static forever; the expiry only
# constrains the moment of capture, never the stored bytes.
#
# The window is deliberately generous (30 minutes, not the production 60
# seconds) so a human running the capture by hand is not racing it.
#
# ── THE MERCHANT BOARD BRANCHES ON FOUR STATES AND THE SEED HAD TWO ───────
#
# The board flow failed on `تیار دی` — the action for a `preparing` order — and
# no fixture ever produced one. Seeding all four LIVE states the board renders
# rather than only the missing one, because the same gap hid a second problem:
# two of the seeded live orders rendered IDENTICALLY while one was waiting for a
# courier and the other had one. A fixture that covers every state a screen
# branches on is the seed equivalent of asserting a whole key set.
#
# ── ON A DIFFERENT CUSTOMER, WHICH IS THIS FILE'S OWN PRECEDENT ───────────
#
# The rig customer keeps **one** live order — that is what makes the status
# screen, the merchant board and the map point at the same thing, and this file
# already records `KQA00003` being moved off that account for exactly this
# reason. The board is the MERCHANT's screen and does not care whose orders
# they are, so these hang off the offer customer.
seed_section "e2e merchant board states" do
  merchant = Merchant.find_by!(phone: "+93700000804")
  item     = merchant.catalog_items.first
  board_customer = e2e_user!(E2E[:offer_customer], name: "QA Offer Customer", role: :customer,
                             email: "qa.offer.customer@karwan.af")

  # `ready` already exists as KQA00003. These are the three the board could not
  # render, each with the timestamps its card reads.
  [
    { code: "KQA00004", status: :placed,    placed: 3.minutes.ago,  accepted: nil,            preparing: nil },
    { code: "KQA00005", status: :accepted,  placed: 12.minutes.ago, accepted: 9.minutes.ago,  preparing: nil },
    { code: "KQA00006", status: :preparing, placed: 20.minutes.ago, accepted: 17.minutes.ago, preparing: 14.minutes.ago },
    # ── TWO MORE, SO A TABLET BOARD IS NOT HALF EMPTY ────────────────────
    #
    # A tablet shows roughly twice what a phone does, so a seed that fills a
    # 360 dp screen leaves an 800 dp one looking unfinished — and "the board
    # looked deliberate" was exactly a layout that was wrong and plausible.
    # Four live cards fill a phone; six start the second column.
    { code: "KQA00007", status: :accepted,  placed: 15.minutes.ago, accepted: 11.minutes.ago, preparing: nil },
    { code: "KQA00008", status: :preparing, placed: 25.minutes.ago, accepted: 22.minutes.ago, preparing: 19.minutes.ago }
  ].each do |row|
    order = Order.find_or_initialize_by(code: row[:code])
    order.assign_attributes(
      customer: board_customer, merchant: merchant, status: row[:status],
      items_total: 260, delivery_fee: 100, commission: 35, courier_fee: 100,
      merchant_payout: 225, customer_total: 360, currency: "AFN",
      payment_method: :cash, payment_status: :pending,
      delivery_latitude: 34.5290, delivery_longitude: 69.1610,
      delivery_landmark_note: "QA fixture — board state #{row[:status]}",
      customer_phone: board_customer.phone,
      placed_at: row[:placed], accepted_at: row[:accepted], preparing_at: row[:preparing]
    )
    order.save!

    if order.order_items.empty?
      order.order_items.create!(catalog_item: item, name: item.name, unit_price: 260,
                                quantity: 1, options_total: 0, line_total: 260, currency: "AFN")
    end
  end
end

# ── THE DEDICATED COURIER HOLDS IT, NOT THE RIG'S OWN ACCOUNT ─────────────
#
# `E2E[:courier]` gets the offer, while the customer account keeps the live JOB
# (KQA00002). `Dispatch::Eligibility`'s `:already_on_a_job` means one courier
# cannot sensibly hold both, and a fixture that contradicts the domain is a
# fixture that teaches the wrong thing. It also means capturing this payload
# needs the COURIER account's token, which the runbook spells out.
seed_section "e2e courier offer and wallet ledger" do
  rig_customer = User.find_by!(phone: E2E[:customer])
  courier      = User.find_by!(phone: E2E[:courier])
  merchant     = Merchant.find_by!(phone: "+93700000804")
  item         = merchant.catalog_items.first

  # ── THE OFFER TARGET BELONGS TO A DIFFERENT CUSTOMER, AND THAT IS A FIX ──
  #
  # The first version put this order on the RIG's customer, which gave that
  # account **two live orders** — `spec/seeds/e2e_spec.rb` caught it
  # immediately on `expect(first.code).to eq("KQA00001")`, because a second
  # `ready` order sorts newest and takes the top of the list.
  #
  # Moving it is the right fix rather than renumbering the assertion, for two
  # reasons. This file's own premise is **ONE live order** for the rig customer
  # — that is what makes the status screen, the merchant board and the map all
  # point at the same thing. And it is truer to the domain: **a courier is
  # offered any customer's order**, and pre-accept they do not see whose it is
  # at all, so tying an offer to the rig's own account was a coincidence
  # pretending to be a relationship.
  # CREATED HERE, not borrowed from `sample.rb`. The first version of this
  # reached for a sample-data customer and `spec/seeds/e2e_spec.rb` failed with
  # `Couldn't find User` — because that spec deliberately loads only
  # `reference.rb` and `e2e.rb`, "so a broken sample.rb cannot fail this spec
  # for an unrelated reason". Its own header says so, and this file has to be
  # self-contained for that to hold.
  offer_customer = e2e_user!(E2E[:offer_customer], name: "QA Offer Customer", role: :customer,
                             email: "qa.offer.customer@karwan.af")

  # In `ready` — the state dispatch offers FROM.
  order = Order.find_or_initialize_by(code: "KQA00003")
  order.assign_attributes(
    customer: offer_customer, merchant: merchant, status: :ready,
    items_total: 260, delivery_fee: 100, commission: 35, courier_fee: 100,
    merchant_payout: 225, customer_total: 360, currency: "AFN",
    payment_method: :cash, payment_status: :pending,
    delivery_latitude: 34.5290, delivery_longitude: 69.1610,
    delivery_landmark_note: "QA fixture — offer target, green door",
    customer_phone: offer_customer.phone,
    placed_at: 8.minutes.ago, accepted_at: 7.minutes.ago,
    preparing_at: 5.minutes.ago, ready_at: 1.minute.ago,
    created_at: 8.minutes.ago
  )
  order.save!
  if order.order_items.none?
    order.order_items.create!(catalog_item: item, name: item.name, unit_price: 260,
                              quantity: 1, options_total: 0, line_total: 260, currency: "AFN")
  end

  offer = Offer.find_or_initialize_by(offerable: order, sequence: 1)
  offer.assign_attributes(
    courier: courier, status: :offered,
    offered_at: 30.seconds.ago, expires_at: 30.minutes.from_now
  )
  offer.save!

  # ── THE LEDGER: one of each kind that matters, so a parser meets them all ─
  #
  # A balance can always be recomputed from entries and entries can never be
  # reconstructed from a balance (CLAUDE.md, one-way door 4) — so `balance_after`
  # is written to match the running total rather than invented per row.
  wallet = courier.courier_wallet || courier.create_courier_wallet!(balance: 0, credit_line: 500)
  # Guarded on THIS section's own rows rather than on the wallet being empty.
  # The accounts section now seeds an opening float, so `none?` would have been
  # false here and these four kinds would never have been written — the rig would
  # have met a ledger of one kind and the parser would never have seen the rest.
  if wallet.wallet_entries.where(kind: :commission).none?
    [
      { kind: :top_up,        amount:  2_000, note: "bank deposit, rider code 41" },
      { kind: :commission,    amount:    -35, note: "KQA00010" },
      { kind: :commission,    amount:    -50, note: "KQA00011" },
      { kind: :reimbursement, amount:    260, note: "customer refused — food returned" },
      { kind: :adjustment,    amount:    -15, note: "counted short at settlement" }
    ].each do |e|
      # `record_entry!` rather than `create!` plus a hand-kept `running` total:
      # one locked entry point owns the arithmetic, so the fixture cannot teach a
      # ledger the app would never write.
      wallet.record_entry!(kind: e[:kind], amount: e[:amount],
                           recorded_by: rig_customer, note: e[:note])
    end
  end
end

seed_section "e2e courier job" do
  customer = User.find_by!(phone: E2E[:customer])
  merchant = Merchant.find_by!(phone: "+93700000804")
  item = merchant.catalog_items.first
  # The RIG'S account carries the job, because the rig signs in as it and
  # switches role. One live job per courier is enforced by
  # `Dispatch::Eligibility`, so there is exactly one.
  courier = customer

  order = Order.find_or_initialize_by(code: "KQA00002")
  order.assign_attributes(
    # A DIFFERENT CUSTOMER from the courier: a courier delivering to himself is
    # a state the app permits and nobody should be looking at while measuring a
    # screen.
    customer: User.find_by!(phone: E2E[:merchant_owner]),
    merchant: merchant, courier: courier, status: :picked_up,
    items_total: 400, delivery_fee: 100, commission: 50, courier_fee: 100,
    merchant_payout: 350, customer_total: 500, currency: "AFN",
    payment_method: :cash, payment_status: :pending,
    delivery_latitude: 34.5400, delivery_longitude: 69.1750,
    delivery_landmark_note: "QA fixture — green door beside the pharmacy",
    customer_phone: E2E[:merchant_owner],
    distance_km: 3.2, duration_minutes: 22, distance_source: "straight_line",
    placed_at: 40.minutes.ago, accepted_at: 38.minutes.ago,
    preparing_at: 35.minutes.ago, ready_at: 25.minutes.ago, picked_up_at: 8.minutes.ago
  )
  order.save!

  if order.order_items.empty?
    order.order_items.create!(catalog_item: item, name: item.name, unit_price: 400,
                              quantity: 1, options_total: 0, line_total: 400, currency: "AFN")
  end

  # The history the courier's step rail reads. Without it every step renders
  # pending on a job that is half done.
  [ %w[placed accepted], %w[accepted preparing], %w[preparing ready], %w[ready picked_up] ]
    .each_with_index do |(from, to), index|
    next if order.transitions.exists?(to_status: to)

    order.transitions.create!(from_status: from, to_status: to, actor: nil,
                              created_at: (38 - (index * 8)).minutes.ago)
  end
end

seed_section "e2e settings" do
  # THE SUPPORT NUMBER. `/public/app_config` serves it and `ScreenContainer`
  # draws the bar only when there is one, so without this row the rig's
  # highest-value RTL assertion has nothing to assert (F-20) — and every screen
  # of every role is missing the thing AFGHAN_UX.md §1 calls "the fallback that
  # always works".
  Setting.find_or_initialize_by(key: "support_phone")
         .update!(value: "+93700000800", value_type: :string,
                  description: Setting::DEFINITIONS["support_phone"][:description])
end
