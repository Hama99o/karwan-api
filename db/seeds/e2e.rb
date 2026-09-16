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
# There is no back door and no injected token. Identity is a phone plus an OTP
# (correction 2), and outside production `POST /auth/otp` returns the code in
# its own response — so a flow types the phone, reads the code and types it,
# which is exactly the path a real user walks. That is what keeps correction 17
# true: no mocks in the app, including for the rig.
#
# THE PHONES ARE THE CONTRACT. `qa/lib/common.sh` holds the same numbers.

# `||=` rather than a bare assignment: this file is re-loadable by design (the
# rig re-seeds between runs, and a spec loads it twice to prove it is
# idempotent), and a bare constant assignment warns on every reload.
E2E ||= {
  customer: "+93700000801",
  merchant_owner: "+93700000802",
  courier: "+93700000803"
}.freeze

def e2e_user!(phone, name:, role:, locale: "ps")
  user = User.find_or_initialize_by(phone: phone)
  user.update!(name: name, locale: locale, last_active_role: role, phone_verified_at: Time.current)
  user.user_roles.find_or_create_by!(role: role)
  user
end

seed_section "e2e accounts" do
  customer = e2e_user!(E2E[:customer], name: "QA Customer", role: :customer)
  owner = e2e_user!(E2E[:merchant_owner], name: "QA Merchant", role: :merchant_owner)
  courier = e2e_user!(E2E[:courier], name: "QA Courier", role: :courier)

  # The customer also HOLDS the other two roles, so the role switch has
  # somewhere to go on one account. F-18 found there is no way back from
  # merchant or courier to customer; a flow cannot even reach the problem
  # without an account that holds all three.
  %i[merchant_owner courier].each { |role| customer.user_roles.find_or_create_by!(role: role) }

  # A merchant the flows name by value.
  merchant = Merchant.find_or_initialize_by(phone: "+93700000804")
  merchant.assign_attributes(
    name: "QA Kabab House", owner: owner, merchant_kind: MerchantKind.first,
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
  profile = courier.courier_profile || CourierProfile.new(user: courier)
  profile.assign_attributes(
    full_name: "QA Courier", national_id_number: "1400-QA-0001",
    guarantor_name: "QA Guarantor", guarantor_phone: "+93700000805",
    vehicle_type: :motorbike, accepted_job_kinds: %w[delivery ride],
    verification_status: :pending, is_available: false
  )
  profile.save!
  %i[id_document selfie].each do |document|
    next if profile.public_send(document).attached?

    profile.public_send(document).attach(
      io: Rails.root.join("spec/fixtures/files/photo.png").open,
      filename: "#{document}.png", content_type: "image/png"
    )
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
  profile.approve!(by: approver) unless profile.verification_approved?
  courier.courier_wallet&.update!(balance: 5_000, credit_line: 500)
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
