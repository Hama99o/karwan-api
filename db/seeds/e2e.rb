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

# `||=` rather than a bare assignment: this file is re-loadable by design (the
# rig re-seeds between runs, and a spec loads it twice to prove it is
# idempotent), and a bare constant assignment warns on every reload.
E2E ||= {
  customer: "+93700000801",
  merchant_owner: "+93700000802",
  courier: "+93700000803"
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
  [ courier, customer ].each do |person|
    person.courier_profile.approve!(by: approver) unless person.courier_profile.verification_approved?
    person.reload.courier_wallet&.update!(balance: 5_000, credit_line: 500)
  end
end

seed_section "e2e live order" do
  customer = User.find_by!(phone: E2E[:customer])
  merchant = Merchant.find_by!(phone: "+93700000804")
  item = merchant.catalog_items.first

  # ONE live order, in `ready` — the state where the most screens have
  # something to show at once: the merchant board has a card, the customer's
  # status screen has a timeline, and the MAP has two points to draw. F-05 has
  # been open across two runs because MapLibre has never been mounted, and the
  # map gates on an active order.
  order = Order.find_or_initialize_by(code: "KQA00001")
  order.assign_attributes(
    customer: customer, merchant: merchant, status: :ready,
    items_total: 400, delivery_fee: 100, commission: 50, courier_fee: 100,
    merchant_payout: 350, customer_total: 500, currency: "AFN",
    payment_method: :cash, payment_status: :pending,
    delivery_latitude: 34.5400, delivery_longitude: 69.1750,
    delivery_landmark_note: "QA fixture — second floor, blue gate",
    customer_phone: customer.phone,
    placed_at: 20.minutes.ago, accepted_at: 18.minutes.ago,
    preparing_at: 15.minutes.ago, ready_at: 2.minutes.ago
  )
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
      picked_up_at: placed + 25.minutes, delivered_at: placed + 40.minutes
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
