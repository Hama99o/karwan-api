# STRESS data: volume, for exercising pagination, indexes and the admin board
# under something like real load.
#
# Opt-in, because nobody wants 20k orders on every `db:seed`:
#
#   KARWAN_SEED_STRESS=1 bin/rails db:seed
#   KARWAN_SEED_STRESS=1 KARWAN_SEED_SCALE=large bin/rails db:seed
#
# Scales:
#   small   (default)  ~40 merchants,  ~150 couriers,  ~2,000 orders
#   large              ~200 merchants, ~600 couriers, ~20,000 orders
#
# Written with `insert_all` rather than `create!`, which is the whole point —
# 20,000 orders one at a time takes minutes and hammers the box. The cost is
# real and must be stated: **insert_all skips validations and callbacks.** So
# this data is deliberately NOT evidence that the model rules hold; the suite is
# for that. Every row here is built to satisfy those rules by construction —
# totals that add up, codes that are unique, a currency on every amount — so the
# volume is realistic rather than merely large.
#
# It also never touches the hand-written sample world, so both can coexist.

SCALE = ENV.fetch("KARWAN_SEED_SCALE", "small")

COUNTS = {
  "small" => { merchants: 40,  couriers: 150, customers: 400,  orders: 2_000,  trips: 400 },
  "large" => { merchants: 200, couriers: 600, customers: 4_000, orders: 20_000, trips: 4_000 }
}.fetch(SCALE) { raise ArgumentError, "KARWAN_SEED_SCALE must be small or large, got #{SCALE.inspect}" }

KABUL_LAT = 34.5553
KABUL_LNG = 69.2075

# A deterministic seed, so a stress run is reproducible: if a query is slow or a
# page renders wrong, the same data comes back.
RNG = Random.new(20_260_915)

def jitter(base, spread = 0.06)
  (base + RNG.rand(-spread..spread)).round(6)
end

def bulk(model, rows, slice: 2_000)
  rows.each_slice(slice) { |batch| model.insert_all(batch) }
end

now = Time.current
puts "  scale=#{SCALE} #{COUNTS.map { |k, v| "#{k}=#{v}" }.join(' ')}"

# Stress rows are identifiable by construction — users and merchants in the
# +9379 phone block, jobs with an 'S' code — which is what makes them safely
# purgeable without touching the hand-written sample world.
#
# Purging on a scale change rather than topping up, because the alternative was
# WORSE THAN EITHER: the first version skipped each section if any stress row
# existed, so `KARWAN_SEED_SCALE=large` against an already-seeded database
# silently did nothing for orders and merchants while still adding couriers.
# Half-applied and quiet. An explicit rebuild is predictable, and at these
# volumes it costs seconds.
def purge_stress!
  stress_user_ids = User.where("phone LIKE '+9379%'").pluck(:id)
  stress_merchant_ids = Merchant.where("phone LIKE '+9379%'").pluck(:id)
  stress_order_ids = Order.where("code LIKE 'S%'").pluck(:id)
  stress_trip_ids = Trip.where("code LIKE 'S%'").pluck(:id)
  stress_wallet_ids = CourierWallet.where(user_id: stress_user_ids).pluck(:id)
  stress_category_ids = CatalogCategory.where(merchant_id: stress_merchant_ids).pluck(:id)

  # Children before parents, or the foreign keys refuse.
  WalletEntry.where(courier_wallet_id: stress_wallet_ids).delete_all
  WalletEntry.where(source_type: "Order", source_id: stress_order_ids).delete_all
  WalletEntry.where(source_type: "Trip", source_id: stress_trip_ids).delete_all
  OrderItemOption.where(order_item_id: OrderItem.where(order_id: stress_order_ids).select(:id)).delete_all
  OrderItem.where(order_id: stress_order_ids).delete_all
  StatusTransition.where(subject_type: "Order", subject_id: stress_order_ids).delete_all
  StatusTransition.where(subject_type: "Trip", subject_id: stress_trip_ids).delete_all
  Offer.where(offerable_type: "Order", offerable_id: stress_order_ids).delete_all
  Offer.where(offerable_type: "Trip", offerable_id: stress_trip_ids).delete_all
  Order.where(id: stress_order_ids).delete_all
  Trip.where(id: stress_trip_ids).delete_all
  CatalogItemOptionValue.where(
    catalog_item_option_id: CatalogItemOption.where(
      catalog_item_id: CatalogItem.where(merchant_id: stress_merchant_ids).select(:id)
    ).select(:id)
  ).delete_all
  CatalogItemOption.where(catalog_item_id: CatalogItem.where(merchant_id: stress_merchant_ids).select(:id)).delete_all
  CatalogItem.where(merchant_id: stress_merchant_ids).delete_all
  CatalogCategory.where(id: stress_category_ids).delete_all
  MerchantCategoryAssignment.where(merchant_id: stress_merchant_ids).delete_all
  MerchantOpeningHour.where(merchant_id: stress_merchant_ids).delete_all
  Merchant.where(id: stress_merchant_ids).delete_all
  Settlement.where(courier_id: stress_user_ids).delete_all
  CourierWallet.where(id: stress_wallet_ids).delete_all
  CourierProfile.where(user_id: stress_user_ids).delete_all
  Address.where(user_id: stress_user_ids).delete_all
  UserRole.where(user_id: stress_user_ids).delete_all
  AuditLog.where(actor_id: stress_user_ids).delete_all
  User.where(id: stress_user_ids).delete_all
end

current_orders = Order.where("code LIKE 'S%'").count
if current_orders.positive? && current_orders != COUNTS[:orders]
  puts "  existing stress volume is #{current_orders} orders, target is #{COUNTS[:orders]} — rebuilding"
  purge_stress!
elsif ActiveModel::Type::Boolean.new.cast(ENV.fetch("KARWAN_SEED_RESET_STRESS", "false"))
  puts "  KARWAN_SEED_RESET_STRESS set — rebuilding"
  purge_stress!
end

# ---------------------------------------------------------------------------
# Users: customers, couriers, merchant owners.
# ---------------------------------------------------------------------------
# The +93 79 block, kept clear of the sample world's +93 70 00 00 0xx numbers so
# the two sets can never collide on the unique phone index.
stress_user_offset = 79_000_0000

seed_section "stress users" do
  existing = User.where("phone LIKE '+9379%'").count
  needed = COUNTS[:customers] + COUNTS[:couriers] + COUNTS[:merchants]
  next if existing >= needed

  rows = (0...needed).map do |i|
    role = if i < COUNTS[:customers] then 0
    elsif i < COUNTS[:customers] + COUNTS[:couriers] then 1
    else 2
    end
    {
      phone: "+93#{stress_user_offset + i}",
      name: "Stress User #{i}",
      locale: %w[fa ps en][i % 3],
      last_active_role: role,
      status: 0,
      phone_verified_at: now,
      created_at: now, updated_at: now
    }
  end
  bulk(User, rows)

  # Roles as their own rows, since `last_active_role` is the hat they last
  # chose and `user_roles` is which hats they hold. The hat actually ON is a
  # fact about a session, which stress data has none of.
  ids = User.where("phone LIKE '+9379%'").order(:id).pluck(:id, :last_active_role)
  bulk(UserRole, ids.map { |id, role| { user_id: id, role: role, created_at: now, updated_at: now } })
end

stress_users = User.where("phone LIKE '+9379%'").order(:id).pluck(:id)
customer_ids = stress_users.first(COUNTS[:customers])
courier_ids  = stress_users[COUNTS[:customers], COUNTS[:couriers]] || []
owner_ids    = stress_users[COUNTS[:customers] + COUNTS[:couriers], COUNTS[:merchants]] || []

seed_section "stress addresses" do
  next if Address.where(user_id: customer_ids).any?

  bulk(Address, customer_ids.map do |id|
    {
      user_id: id, label: "Home",
      latitude: jitter(KABUL_LAT), longitude: jitter(KABUL_LNG),
      landmark_note: "Landmark note for stress address #{id}",
      is_default: true, has_voice_note: false,
      created_at: now, updated_at: now
    }
  end)
end

seed_section "stress couriers" do
  next if CourierProfile.where(user_id: courier_ids).any?

  bulk(CourierProfile, courier_ids.each_with_index.map do |id, i|
    {
      user_id: id,
      # A realistic mix: most approved, a tenth still pending, two thirds on
      # shift. An admin board that only ever sees healthy rows is not tested.
      verification_status: (i % 10).zero? ? 0 : 1,
      is_available: (i % 3) != 0,
      accepted_job_kinds: (i % 4).zero? ? %w[delivery ride] : %w[delivery],
      vehicle_type: [ 0, 0, 0, 1, 2 ][i % 5],
      full_name: "Stress Courier #{i}",
      national_id_number: "1490#{i.to_s.rjust(8, '0')}",
      guarantor_name: "Guarantor #{i}",
      guarantor_phone: "+9378#{i.to_s.rjust(7, '0')}",
      last_latitude: jitter(KABUL_LAT, 0.04), last_longitude: jitter(KABUL_LNG, 0.04),
      location_updated_at: now - RNG.rand(0..600).seconds,
      created_at: now, updated_at: now
    }
  end)

  bulk(CourierWallet, courier_ids.each_with_index.map do |id, i|
    {
      user_id: id, balance: RNG.rand(-400..5_000), credit_line: 500, currency: "AFN",
      # Offset well clear of the 4-digit sample codes, and unique by
      # construction rather than by retrying a random draw 600 times.
      top_up_code: (2_000 + i).to_s,
      created_at: now, updated_at: now
    }
  end)
end

courier_wallet_by_user = CourierWallet.where(user_id: courier_ids).pluck(:user_id, :id).to_h

# ---------------------------------------------------------------------------
# Merchants and catalogs.
# ---------------------------------------------------------------------------
seed_section "stress merchants and catalogs" do
  next if Merchant.where("phone LIKE '+9379%'").any?

  kind_ids = MerchantKind.order(:position).pluck(:id)
  raise "run the reference seeds first" if kind_ids.empty?

  bulk(Merchant, COUNTS[:merchants].times.map do |i|
    {
      merchant_kind_id: kind_ids[i % kind_ids.size],
      owner_id: owner_ids[i],
      name: "Stress Merchant #{i} Kabab House",
      phone: "+9379#{(500_0000 + i)}",
      is_open: (i % 5) != 0,
      status: (i % 12).zero? ? 0 : 1,
      prep_time_minutes: (i % 3).zero? ? nil : 15 + (i % 30),
      latitude: jitter(KABUL_LAT, 0.05), longitude: jitter(KABUL_LNG, 0.05),
      landmark_note: "Near landmark #{i}",
      commission_rate: [ 0.1, 0.125, 0.15 ][i % 3],
      owner_name: "Owner #{i}", owner_phone: "+9379#{(600_0000 + i)}",
      created_at: now, updated_at: now
    }
  end)

  merchant_ids = Merchant.where("phone LIKE '+9379%'").order(:id).pluck(:id)

  # Browse categories, so filtering by cuisine has something to filter.
  category_ids = MerchantCategory.order(:position).pluck(:id)
  bulk(MerchantCategoryAssignment, merchant_ids.each_with_index.flat_map do |mid, i|
    category_ids.values_at(i % category_ids.size, (i + 3) % category_ids.size).uniq.map do |cid|
      { merchant_id: mid, merchant_category_id: cid, created_at: now, updated_at: now }
    end
  end)

  # Three catalog categories each, so a merchant screen has sections.
  bulk(CatalogCategory, merchant_ids.flat_map do |mid|
    [ "Starters", "Mains", "Drinks" ].each_with_index.map do |name, pos|
      { merchant_id: mid, name: name, position: pos, created_at: now, updated_at: now }
    end
  end)

  cats = CatalogCategory.where(merchant_id: merchant_ids).pluck(:id, :merchant_id)

  # Eight items per category — enough that a merchant screen needs scrolling
  # and a catalog list needs pages.
  dishes = [ "Chicken Kabab", "Lamb Kabab", "Qabuli Palaw", "Mantu", "Ashak",
             "Bolani", "Doogh", "Green Tea", "Firni", "Burger", "Pizza", "Naan" ]
  bulk(CatalogItem, cats.flat_map do |cat_id, merchant_id|
    8.times.map do |i|
      {
        merchant_id: merchant_id, catalog_category_id: cat_id,
        name: "#{dishes[(cat_id + i) % dishes.size]} #{i + 1}",
        description: "Stress item #{cat_id}-#{i}",
        price: [ 80, 120, 250, 320, 400, 450, 550 ][(cat_id + i) % 7],
        currency: "AFN",
        # A tenth sold out, because that state has to render.
        is_available: ((cat_id + i) % 10) != 0,
        position: i, created_at: now, updated_at: now
      }
    end
  end)
end

merchant_ids = Merchant.where("phone LIKE '+9379%'").order(:id).pluck(:id)
item_by_merchant = CatalogItem.where(merchant_id: merchant_ids).pluck(:merchant_id, :id, :name, :price)
                              .group_by(&:first)

# ---------------------------------------------------------------------------
# Orders: spread over 90 days, across every state, with line items.
# ---------------------------------------------------------------------------
seed_section "stress orders" do
  next if Order.where("code LIKE 'S%'").any?

  # Weighted so the mix looks like a real business rather than a uniform
  # spread: most orders completed, a minority live, a realistic tail of
  # rejections, cancellations and failures.
  status_mix = ([ 5 ] * 70) + ([ 0, 1, 2, 3, 4 ] * 4) + ([ 6 ] * 4) + ([ 7 ] * 4) + ([ 8 ] * 2)

  rows = COUNTS[:orders].times.map do |i|
    merchant_id = merchant_ids[i % merchant_ids.size]
    status = status_mix[i % status_mix.size]
    delivered = status == 5
    assigned = [ 2, 3, 4, 5, 8 ].include?(status)
    courier_id = assigned ? courier_ids[i % courier_ids.size] : nil

    items_total = [ 250, 320, 400, 450, 550, 700, 900 ][i % 7]
    commission = (items_total * 0.125).round(2)
    placed_at = now - RNG.rand(0..90).days - RNG.rand(0..86_399).seconds

    {
      # 'S' prefix so stress orders are trivially separable from real ones and
      # from the sample world's 'K' codes.
      code: "S#{i.to_s.rjust(9, '0')}",
      customer_id: customer_ids[i % customer_ids.size],
      merchant_id: merchant_id,
      courier_id: courier_id,
      items_total: items_total, delivery_fee: 100, commission: commission,
      courier_fee: 100, merchant_payout: items_total - commission,
      customer_total: items_total + 100, currency: "AFN",
      payment_method: 0, status: status,
      payment_status: delivered ? ((i % 3).zero? ? 2 : 1) : 0,
      delivery_latitude: jitter(KABUL_LAT), delivery_longitude: jitter(KABUL_LNG),
      delivery_landmark_note: "Stress delivery landmark #{i}",
      customer_phone: "+93#{stress_user_offset + (i % COUNTS[:customers])}",
      placed_at: placed_at,
      accepted_at: status >= 1 && status != 6 && status != 7 ? placed_at + 3.minutes : nil,
      preparing_at: status >= 2 && status < 6 ? placed_at + 6.minutes : nil,
      ready_at: status >= 3 && status < 6 ? placed_at + 18.minutes : nil,
      picked_up_at: status >= 4 && status < 6 ? placed_at + 24.minutes : nil,
      merchant_paid_at: status >= 4 && status < 6 ? placed_at + 24.minutes : nil,
      delivered_at: delivered ? placed_at + 38.minutes : nil,
      rejected_at: status == 6 ? placed_at + 2.minutes : nil,
      cancelled_at: status == 7 ? placed_at + 4.minutes : nil,
      failed_at: status == 8 ? placed_at + 40.minutes : nil,
      created_at: placed_at, updated_at: placed_at
    }
  end
  bulk(Order, rows)
end

seed_section "stress order items" do
  order_rows = Order.where("code LIKE 'S%'").pluck(:id, :merchant_id, :items_total)
  next if OrderItem.where(order_id: order_rows.first(1).map(&:first)).any?

  bulk(OrderItem, order_rows.map do |order_id, merchant_id, items_total|
    candidates = item_by_merchant[merchant_id] || []
    chosen = candidates[order_id % candidates.size] if candidates.any?
    {
      order_id: order_id,
      catalog_item_id: chosen&.at(1),
      # Snapshot, never a live join — the name and price as they were.
      name: chosen&.at(2) || "Stress item",
      unit_price: items_total, options_total: 0, quantity: 1,
      line_total: items_total, currency: "AFN",
      created_at: now, updated_at: now
    }
  end)
end

# ---------------------------------------------------------------------------
# Rides, on the same courier pool.
# ---------------------------------------------------------------------------
seed_section "stress rides" do
  next if Trip.where("code LIKE 'S%'").any?
  next if courier_ids.empty?

  ride_couriers = CourierProfile.where(user_id: courier_ids)
                                .where("accepted_job_kinds @> ARRAY['ride']::varchar[]")
                                .pluck(:user_id)
  next if ride_couriers.empty?

  status_mix = ([ 4 ] * 70) + ([ 0, 1, 2, 3 ] * 5) + ([ 5 ] * 6) + ([ 6 ] * 4)

  bulk(Trip, COUNTS[:trips].times.map do |i|
    status = status_mix[i % status_mix.size]
    completed = status == 4
    assigned = [ 1, 2, 3, 4, 6 ].include?(status)
    distance = (1.5 + RNG.rand(0.0..12.0)).round(3)
    fare = [ 80, (50 + (distance * 25)).round(2) ].max
    commission = (fare * 0.125).round(2)
    requested_at = now - RNG.rand(0..90).days - RNG.rand(0..86_399).seconds

    {
      code: "S#{i.to_s.rjust(9, '0')}",
      passenger_id: customer_ids[i % customer_ids.size],
      courier_id: assigned ? ride_couriers[i % ride_couriers.size] : nil,
      pickup_latitude: jitter(KABUL_LAT), pickup_longitude: jitter(KABUL_LNG),
      pickup_landmark_note: "Stress pickup #{i}",
      dropoff_latitude: jitter(KABUL_LAT), dropoff_longitude: jitter(KABUL_LNG),
      dropoff_landmark_note: "Stress dropoff #{i}",
      passenger_phone: "+93#{stress_user_offset + (i % COUNTS[:customers])}",
      distance_km: distance, duration_minutes: (distance / 18.0 * 60).ceil,
      fare: fare, commission: commission, courier_earnings: (fare - commission).round(2),
      currency: "AFN", payment_method: 0, status: status,
      payment_status: completed ? ((i % 3).zero? ? 2 : 1) : 0,
      requested_at: requested_at,
      accepted_at: status >= 1 && status < 5 ? requested_at + 2.minutes : nil,
      arrived_at: status >= 2 && status < 5 ? requested_at + 7.minutes : nil,
      in_progress_at: status >= 3 && status < 5 ? requested_at + 9.minutes : nil,
      completed_at: completed ? requested_at + 25.minutes : nil,
      cancelled_at: status == 5 ? requested_at + 3.minutes : nil,
      failed_at: status == 6 ? requested_at + 12.minutes : nil,
      created_at: requested_at, updated_at: requested_at
    }
  end)
end

# ---------------------------------------------------------------------------
# Ledger entries for the completed work, so wallet screens have pages.
# ---------------------------------------------------------------------------
seed_section "stress wallet entries" do
  next if WalletEntry.where(note: "stress commission").any?

  delivered = Order.where("code LIKE 'S%'").where(status: :delivered)
                   .where.not(courier_id: nil)
                   .pluck(:id, :courier_id, :commission)

  rows = delivered.map do |order_id, courier_id, commission|
    wallet_id = courier_wallet_by_user[courier_id]
    next unless wallet_id

    {
      courier_wallet_id: wallet_id, source_type: "Order", source_id: order_id,
      kind: 0, amount: -commission, currency: "AFN",
      # Deliberately not a running balance: these are inserted in bulk out of
      # order, so a per-row running total would be fiction. The real path is
      # CourierWallet#record_entry!, which the suite covers.
      balance_after: 0,
      note: "stress commission", created_at: now
    }
  end.compact

  bulk(WalletEntry, rows)
end

puts "  stress totals: merchants=#{Merchant.count} catalog_items=#{CatalogItem.count} " \
     "couriers=#{CourierProfile.count} orders=#{Order.count} trips=#{Trip.count} " \
     "order_items=#{OrderItem.count} wallet_entries=#{WalletEntry.count}"
