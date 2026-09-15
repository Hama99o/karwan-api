# Sample data: a world you can actually place an order in.
#
# Development and test only — db/seeds.rb refuses to load this in production.
# Idempotent, so re-running it does not duplicate anyone.
#
# Every phone number is in the +93 70 00 00 0xx block so the whole set is
# recognisable at a glance and cannot collide with a real number.

KABUL = { lat: 34.5553, lng: 69.2075 }.freeze

def find_user!(phone, name:, role:, locale: "fa")
  user = User.find_or_initialize_by(phone: phone)
  user.update!(name: name, locale: locale, active_role: role, phone_verified_at: Time.current)
  user.user_roles.find_or_create_by!(role: role)
  user
end

seed_section "admin and support" do
  find_user!("+93700000001", name: "Karwan Admin", role: :admin, locale: "en")
  find_user!("+93700000002", name: "Najibullah (Kabul ops)", role: :admin)
end

seed_section "customers" do
  [
    [ "+93700000010", "احمد کریمی",   "fa" ],
    [ "+93700000011", "روya نظری",    "fa" ],
    [ "+93700000012", "زلمی خان",     "ps" ],
    [ "+93700000013", "Sara Ahmadi",  "en" ]
  ].each do |phone, name, locale|
    customer = find_user!(phone, name: name, role: :customer, locale: locale)

    # An address is a PIN, a VOICE NOTE and a PHONE — never a typed street
    # address. The landmark text here stands in for what a customer would
    # normally record as audio.
    Address.find_or_create_by!(user: customer, label: "Home") do |address|
      address.latitude = KABUL[:lat] + rand(-0.012..0.012)
      address.longitude = KABUL[:lng] + rand(-0.012..0.012)
      address.landmark_note = "دروازه آبی نزدیک پارک شهر نو، طبقه دوم"
      address.phone = phone
      address.is_default = true
    end
  end
end

seed_section "couriers" do
  # Deliberately a spread of real operational states, because every one of them
  # has to be visible and fixable in the admin console:
  #   - one approved, on shift, takes both demand types
  #   - one approved, on shift, deliveries only
  #   - one approved but off shift
  #   - one still pending approval (incomplete is legal while pending)
  #   - one blocked by an empty wallet, which is the state that stops dispatch
  [
    { phone: "+93700000020", name: "عبدالله رحیمی", kinds: %w[delivery ride], vehicle: :motorbike,
      status: :approved, available: true,  balance: 1_200, credit: 500 },
    { phone: "+93700000021", name: "میرویس احمدی", kinds: %w[delivery],      vehicle: :bicycle,
      status: :approved, available: true,  balance: 300,   credit: 500 },
    { phone: "+93700000022", name: "نصیر جان",     kinds: %w[delivery ride], vehicle: :car,
      status: :approved, available: false, balance: 2_000, credit: 1_000 },
    { phone: "+93700000023", name: "فرید حسینی",   kinds: %w[delivery],      vehicle: :motorbike,
      status: :pending,  available: false, balance: 0,     credit: 0 },
    { phone: "+93700000024", name: "جاوید نوری",   kinds: %w[delivery],      vehicle: :motorbike,
      status: :approved, available: true,  balance: -500,  credit: 500 }
  ].each_with_index do |data, index|
    courier = find_user!(data[:phone], name: data[:name], role: :courier)

    profile = CourierProfile.find_or_initialize_by(user: courier)
    profile.assign_attributes(
      is_available: data[:available],
      accepted_job_kinds: data[:kinds],
      vehicle_type: data[:vehicle],
      full_name: data[:name],
      father_name: "محمد",
      national_id_number: "1400#{(index + 1).to_s.rjust(8, '0')}",
      plate_number: "KBL-#{1000 + index}",
      guarantor_name: "حاجی عبدالرحمن",
      guarantor_phone: "+9370000009#{index}",
      guarantor_relation: "uncle",
      work_area: "شهر نو",
      last_latitude: KABUL[:lat] + rand(-0.008..0.008),
      last_longitude: KABUL[:lng] + rand(-0.008..0.008),
      location_updated_at: Time.current
    )
    profile.verification_status = data[:status]
    if data[:status] == :approved
      profile.verified_at ||= 1.week.ago
      profile.verified_by ||= User.find_by(phone: "+93700000001")
    end
    profile.save!

    wallet = CourierWallet.find_or_initialize_by(user: courier)
    wallet.credit_line = data[:credit]
    wallet.balance = 0 if wallet.new_record?
    wallet.save!

    # Built from ledger entries rather than by setting the balance directly,
    # because a balance that was never written as entries is exactly the state
    # one-way door #4 exists to prevent — and the seed should demonstrate the
    # real path, not a shortcut around it.
    next unless wallet.wallet_entries.empty?

    admin = User.find_by(phone: "+93700000001")
    if data[:balance].positive?
      wallet.record_entry!(kind: :top_up, amount: data[:balance], recorded_by: admin,
                           note: "Opening deposit, reconciled from bank statement")
    elsif data[:balance].negative?
      wallet.record_entry!(kind: :top_up, amount: 200, recorded_by: admin, note: "Opening deposit")
      wallet.record_entry!(kind: :commission, amount: -700, recorded_by: admin,
                           note: "Accrued commission — wallet now blocked")
    end
  end
end

seed_section "merchants and catalogs" do
  restaurant_kind = MerchantKind.find_by!(slug: "restaurant")
  bookshop_kind = MerchantKind.find_by!(slug: "bookshop")
  pharmacy_kind = MerchantKind.find_by!(slug: "pharmacy")

  admin = User.find_by(phone: "+93700000001")

  merchants = [
    {
      phone: "+93700000030", name: "کباب شهر نو", kind: restaurant_kind,
      owner_phone: "+93700000040", owner_name: "حاجی گل محمد",
      categories: %w[kabab qabuli drinks], prep: 20, is_open: true,
      catalog: {
        "کباب و بریانی" => [
          { name: "کباب مرغ", en: "Chicken Kabab", price: 400, desc: "Charcoal grilled, served with naan" },
          { name: "کباب چوپان", en: "Lamb Kabab", price: 550, desc: "Lamb, charcoal grilled" },
          { name: "قابلی پلو", en: "Qabuli Palaw", price: 450, desc: "Rice, lamb, carrot and raisin" }
        ],
        "نوشیدنی" => [
          { name: "دوغ", en: "Doogh", price: 60, desc: "Salted yoghurt drink" },
          { name: "چای سبز", en: "Green tea", price: 30, desc: "Pot" }
        ]
      }
    },
    {
      phone: "+93700000031", name: "منتو خانه کابل", kind: restaurant_kind,
      owner_phone: "+93700000041", owner_name: "بی بی حلیمه",
      categories: %w[mantu ashak bolani], prep: 30, is_open: true,
      catalog: {
        "غذای خانگی" => [
          { name: "منتو", en: "Mantu", price: 350, desc: "Steamed dumplings, minced beef" },
          { name: "آشک", en: "Ashak", price: 320, desc: "Leek dumplings with yoghurt" },
          { name: "بولانی", en: "Bolani", price: 120, desc: "Stuffed flatbread, potato" }
        ]
      }
    },
    {
      phone: "+93700000032", name: "کتاب فروشی دانش", kind: bookshop_kind,
      owner_phone: "+93700000042", owner_name: "استاد سمیع",
      categories: %w[books], prep: nil, is_open: true,
      catalog: {
        "کتاب‌ها" => [
          { name: "دیوان حافظ", en: "Divan of Hafez", price: 600, desc: "Hardcover" },
          { name: "شاهنامه", en: "Shahnameh", price: 850, desc: "Illustrated edition" }
        ]
      }
    },
    {
      phone: "+93700000033", name: "دواخانه شفا", kind: pharmacy_kind,
      owner_phone: "+93700000043", owner_name: "دکتور نجیب",
      categories: %w[medicine], prep: nil, is_open: false,
      catalog: {
        "دوا" => [
          { name: "پاراسیتامول", en: "Paracetamol 500mg", price: 80, desc: "Box of 20" }
        ]
      }
    }
  ]

  merchants.each do |data|
    owner = find_user!(data[:owner_phone], name: data[:owner_name], role: :merchant_owner)

    merchant = Merchant.find_or_initialize_by(phone: data[:phone])
    merchant.assign_attributes(
      name: data[:name], merchant_kind: data[:kind], owner: owner,
      is_open: data[:is_open], status: :active,
      prep_time_minutes: data[:prep],
      latitude: KABUL[:lat] + rand(-0.010..0.010),
      longitude: KABUL[:lng] + rand(-0.010..0.010),
      landmark_note: "روبروی مسجد شهر نو",
      commission_rate: 0.125,
      owner_name: data[:owner_name], owner_phone: data[:owner_phone],
      contact_person_name: data[:owner_name], contact_person_phone: data[:owner_phone],
      verified_at: merchant.verified_at || 2.weeks.ago,
      verified_by: merchant.verified_by || admin
    )
    merchant.save!

    data[:categories].each do |slug|
      category = MerchantCategory.find_by!(slug: slug)
      MerchantCategoryAssignment.find_or_create_by!(merchant: merchant, merchant_category: category)
    end

    # Open every day, 09:00-22:00. Advisory only — `is_open` is the authority.
    (0..6).each do |day|
      MerchantOpeningHour.find_or_create_by!(merchant: merchant, day_of_week: day) do |hours|
        hours.opens_at = "09:00"
        hours.closes_at = "22:00"
      end
    end

    data[:catalog].each_with_index do |(category_name, items), category_index|
      category = CatalogCategory.find_or_initialize_by(merchant: merchant, name: category_name)
      category.position = category_index
      category.save!

      items.each_with_index do |item, item_index|
        record = CatalogItem.find_or_initialize_by(catalog_category: category, name: item[:name])
        record.assign_attributes(
          merchant: merchant, description: item[:desc], price: item[:price],
          is_available: true, position: item_index
        )
        record.save!
      end
    end
  end

  # Options on one item only, and one level deep. A size choice and some
  # extras is the whole shape — this is a menu, not a configurator.
  kabab = CatalogItem.find_by(name: "کباب مرغ")
  if kabab && kabab.options.empty?
    size = kabab.options.create!(name: "اندازه", selection_type: :single, required: true,
                                 min_selections: 1, max_selections: 1, position: 0)
    size.values.create!(name: "عادی", price_delta: 0, position: 0)
    size.values.create!(name: "کلان", price_delta: 150, position: 1)

    extras = kabab.options.create!(name: "اضافات", selection_type: :multiple,
                                   min_selections: 0, max_selections: 3, position: 1)
    extras.values.create!(name: "نان اضافی", price_delta: 20, position: 0)
    extras.values.create!(name: "سالاد", price_delta: 50, position: 1)
    extras.values.create!(name: "چتنی", price_delta: 10, position: 2)
  end

  # A sold-out item, because the admin console and the customer app both have to
  # render one and it is the toggle a merchant uses most.
  CatalogItem.find_by(name: "کباب چوپان")&.update!(is_available: false)
end

seed_section "orders across every state" do
  next if Order.any?

  merchant = Merchant.find_by!(phone: "+93700000030")
  customer = User.find_by!(phone: "+93700000010")
  address = customer.addresses.first
  courier = User.find_by!(phone: "+93700000020")
  owner = merchant.owner
  admin = User.find_by(phone: "+93700000001")

  # One order per state that someone has to look at in the admin console. The
  # money follows the brief's worked example so the numbers are checkable
  # against the document: items 400, delivery 100, commission 50, total 500,
  # merchant paid 350, courier keeps 100 and holds our 50.
  states = [
    { status: :placed,    payment: :pending,   courier: nil,     note: "Waiting for the merchant" },
    { status: :accepted,  payment: :pending,   courier: nil,     note: nil },
    { status: :preparing, payment: :pending,   courier: courier, note: "Extra chutney please" },
    { status: :ready,     payment: :pending,   courier: courier, note: nil },
    { status: :picked_up, payment: :pending,   courier: courier, note: nil },
    { status: :delivered, payment: :collected, courier: courier, note: nil },
    { status: :delivered, payment: :settled,   courier: courier, note: nil },
    { status: :rejected,  payment: :pending,   courier: nil,     note: nil },
    { status: :cancelled, payment: :pending,   courier: nil,     note: nil },
    { status: :failed,    payment: :pending,   courier: courier, note: nil }
  ]

  states.each_with_index do |state, index|
    placed_at = (states.size - index).hours.ago

    order = Order.create!(
      customer: customer, merchant: merchant, courier: state[:courier],
      items_total: 400, delivery_fee: 100, commission: 50, courier_fee: 100,
      merchant_payout: 350, customer_total: 500, currency: "AFN",
      payment_method: :cash, status: state[:status], payment_status: state[:payment],
      delivery_latitude: address.latitude, delivery_longitude: address.longitude,
      delivery_landmark_note: address.landmark_note,
      customer_phone: customer.phone, notes: state[:note],
      placed_at: placed_at
    )

    # Snapshot line items — never a live join to the catalog.
    item = order.order_items.create!(
      catalog_item: CatalogItem.find_by(name: "کباب مرغ"),
      name: "کباب مرغ", unit_price: 400, options_total: 0, quantity: 1,
      line_total: 400, currency: "AFN"
    )
    item.selected_options.create!(option_name: "اندازه", value_name: "عادی", price_delta: 0)

    # Timestamps and a transition log per state reached, so the admin board's
    # staleness colouring and "how long in preparing" both have real data.
    reached = case state[:status]
    when :placed     then []
    when :accepted   then %i[accepted]
    when :preparing  then %i[accepted preparing]
    when :ready      then %i[accepted preparing ready]
    when :picked_up  then %i[accepted preparing ready picked_up]
    when :delivered  then %i[accepted preparing ready picked_up delivered]
    when :rejected   then %i[rejected]
    when :cancelled  then %i[cancelled]
    when :failed     then %i[accepted preparing ready picked_up failed]
    end

    previous = "placed"
    reached.each_with_index do |status, step|
      at = placed_at + ((step + 1) * 6).minutes
      order.update_columns("#{status}_at" => at)
      actor, role = case status
      when :accepted, :preparing, :ready, :rejected then [ owner, :merchant_owner ]
      when :picked_up, :delivered, :failed then [ state[:courier], :courier ]
      else [ admin, :admin ]
      end
      order.transitions.create!(from_status: previous, to_status: status.to_s,
                                actor: actor, actor_role: role, created_at: at)
      previous = status.to_s
    end

    order.update_columns(merchant_paid_at: order.picked_up_at) if order.picked_up_at
    order.update_columns(settled_at: Time.current) if state[:payment] == :settled
    order.update!(failure_reason: :customer_refused) if state[:status] == :failed
    order.update!(rejection_reason: :too_busy) if state[:status] == :rejected
    if state[:status] == :cancelled
      order.update!(cancellation_reason: :customer_changed_mind, cancelled_by_role: :customer)
    end

    # The commission is charged to the courier's wallet on delivery, as a real
    # ledger entry against the order.
    if state[:status] == :delivered && state[:courier]
      wallet = state[:courier].courier_wallet
      wallet.record_entry!(kind: :commission, amount: -50, source: order, recorded_by: admin,
                           note: "Commission on #{order.code}")
    end

    # The platform absorbs a refused order and reimburses the courier the same
    # day — a written policy in CLAUDE.md, seeded so it is visible rather than
    # theoretical.
    if state[:status] == :failed && state[:courier]
      wallet = state[:courier].courier_wallet
      wallet.record_entry!(kind: :reimbursement, amount: 350, source: order, recorded_by: admin,
                           note: "Customer refused — platform absorbs the food cost")
    end
  end

  # An unassigned order with exhausted offers, which is the case that has to
  # reach a human. Dispatch gives up after N tries and admin assigns by hand.
  stuck = Order.find_by(status: "accepted")
  if stuck && stuck.offers.empty?
    CourierProfile.dispatchable_for(:delivery).limit(2).each_with_index do |profile, index|
      stuck.offers.create!(
        courier: profile.user, sequence: index + 1, status: :timed_out,
        offered_at: 20.minutes.ago + (index * 2).minutes,
        expires_at: 19.minutes.ago + (index * 2).minutes
      )
    end
  end
end

seed_section "rides" do
  next if Trip.any?

  passenger = User.find_by!(phone: "+93700000011")
  courier = User.find_by!(phone: "+93700000020")
  admin = User.find_by(phone: "+93700000001")

  # Schema only — there is no ride product yet. Seeded so the admin console can
  # render both demand types on one board from day one, which is the whole
  # point of the shared dispatch.
  #
  # base 50 + 4.2km x 25 = 155, commission 12.5% = 19.38, courier keeps 135.62.
  [
    { status: :requested, payment: :pending,   courier: nil },
    { status: :in_progress, payment: :pending, courier: courier },
    { status: :completed, payment: :collected, courier: courier }
  ].each_with_index do |state, index|
    requested_at = (3 - index).hours.ago

    trip = Trip.create!(
      passenger: passenger, courier: state[:courier],
      pickup_latitude: KABUL[:lat], pickup_longitude: KABUL[:lng],
      pickup_landmark_note: "دروازه آبی نزدیک پارک شهر نو",
      dropoff_latitude: 34.5658, dropoff_longitude: 69.2123,
      dropoff_landmark_note: "میدان هوایی کابل",
      passenger_phone: passenger.phone,
      distance_km: 4.2, duration_minutes: 14,
      fare: 155, commission: 19.38, courier_earnings: 135.62, currency: "AFN",
      payment_method: :cash, status: state[:status], payment_status: state[:payment],
      requested_at: requested_at
    )

    reached = case state[:status]
    when :requested   then []
    when :in_progress then %i[accepted arrived in_progress]
    when :completed   then %i[accepted arrived in_progress completed]
    end

    previous = "requested"
    reached.each_with_index do |status, step|
      at = requested_at + ((step + 1) * 4).minutes
      trip.update_columns("#{status}_at" => at)
      trip.transitions.create!(from_status: previous, to_status: status.to_s,
                               actor: state[:courier], actor_role: :courier, created_at: at)
      previous = status.to_s
    end

    next unless state[:status] == :completed

    state[:courier].courier_wallet.record_entry!(
      kind: :commission, amount: -19.38, source: trip, recorded_by: admin,
      note: "Commission on ride #{trip.code}"
    )
  end
end

seed_section "settlement and audit trail" do
  courier = User.find_by!(phone: "+93700000020")
  admin = User.find_by(phone: "+93700000001")

  if Settlement.none?
    # Expected AND counted, both stored, with the named person who counted.
    # One balanced, one short — because a mismatch is normal and the admin
    # screen has to show both.
    Settlement.find_or_create_by!(courier: courier, settled_at: 2.days.ago) do |settlement|
      settlement.expected_amount = 500
      settlement.counted_amount = 500
      settlement.currency = "AFN"
      settlement.counted_by_name = "Najibullah (Kabul office)"
      settlement.counted_by = User.find_by(phone: "+93700000002")
      settlement.note = "Balanced"
    end

    Settlement.find_or_create_by!(courier: courier, settled_at: 1.day.ago) do |settlement|
      settlement.expected_amount = 450
      settlement.counted_amount = 400
      settlement.currency = "AFN"
      settlement.counted_by_name = "Najibullah (Kabul office)"
      settlement.counted_by = User.find_by(phone: "+93700000002")
      settlement.note = "50 short — courier says change float, to re-check"
    end
  end

  next if AuditLog.any?

  # Every admin intervention leaves a row. Seeded so the audit screen is not
  # empty on first look, and so its shape is exercised.
  order = Order.find_by(status: "failed")
  AuditLog.record!(
    action: "order.marked_failed", actor: admin, actor_role: :admin, target: order,
    before: { status: "picked_up" }, after: { status: "failed", failure_reason: "customer_refused" },
    details: { note: "Customer refused at the door; courier reimbursed the same day" }
  )
  AuditLog.record!(
    action: "wallet.credited", actor: admin, actor_role: :admin, target: courier,
    before: { balance: "0.0" }, after: { balance: "1200.0" },
    details: { note: "Opening deposit reconciled from bank statement", top_up_code: courier.courier_wallet.top_up_code }
  )
end
