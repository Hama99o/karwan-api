# Reference data. Every environment, idempotent, safe after a deploy.

# ── THE FIRST ADMIN, WITHOUT WHOM THE CONSOLE CANNOT BE OPENED ─────────────
#
# COPIED FROM hatiwal-api/db/seeds.rb:12-28 (correction 15), which solves this
# and which Karwan had not copied.
#
# Found by booting the production image against an empty database on
# 2026-09-17: the seed ran, 48 settings appeared, and `admin_users` was **0**.
# `AdminUser` was created in `db/seeds/sample.rb` and `db/seeds/e2e.rb` ONLY,
# and both are skipped in production — so a first deploy produced a working API
# with an ops console **nobody could log into**, and the `admin` alias in
# `deploy.yml` only counts them. Every gate green, nothing broken, unusable.
#
# THE PASSWORD IS NEVER DEFAULTED IN PRODUCTION. Raising is deliberate and is
# Hatiwal's choice: a console seeded with a known password is worse than no
# console, because it is reachable by anyone who has read this file. The raise
# lands during `db:prepare` on first boot, so the deploy fails loudly with the
# remedy in the message rather than coming up quietly compromised.
seed_section "admin user" do
  # PRODUCTION ONLY, and that is the point rather than a shortcut.
  # `db/seeds/sample.rb` already creates `ops@karwan.af` with the password the
  # QA rig signs in with, and it runs after this file — so seeding one here in
  # development would either be immediately overwritten or, worse, silently
  # change the rig's credentials the day somebody reorders these loads.
  #
  # The gap is production-shaped: it is the ONLY environment where neither
  # `sample.rb` nor `e2e.rb` runs, and therefore the only one that ends up with
  # no admin at all. Both branches are asserted in
  # spec/seeds/reference_admin_spec.rb.
  #
  # MEASURED, NOT PREDICTED: the first version of this had no guard, and it
  # broke `spec/seeds/e2e_spec.rb` — `e2e.rb` resolves its approver with
  # `find_or_create_by!(email: "ops@karwan.af")`, found the account this file
  # had already made, and skipped its own block. I ran the e2e example with
  # this file reverted and with it restored to find that out, having first
  # assumed the failure belonged to the session editing that seed. It did not.
  next unless Rails.env.production?

  email = ENV.fetch("ADMIN_EMAIL", "ops@karwan.af")
  password = ENV.fetch("ADMIN_PASSWORD") do
    if Rails.env.production?
      raise "ADMIN_PASSWORD must be set to seed the admin user in production — " \
            "refusing to create an admin with a known default password. " \
            "Set it in .env.production and redeploy."
    end

    "changeme123!" # development and test only — the guard above keeps it there
  end

  admin = AdminUser.find_or_initialize_by(email: email)
  if admin.new_record?
    admin.name = ENV.fetch("ADMIN_NAME", "Karwan Ops")
    admin.password = password
    admin.save!
  end
end

seed_section "settings" do
  # Refreshes descriptions and currencies (ours) without overwriting values an
  # admin has tuned (theirs). Asserted by a spec, because silently resetting
  # the delivery fee on a deploy is the kind of bug nobody notices until a
  # courier is underpaid.
  Setting.seed_defaults!
end

seed_section "pricing rates" do
  # The per-vehicle tariffs. Same discipline as settings: creates what is
  # missing and NEVER overwrites a number Hamma9900 has typed, because
  # silently repricing every ride on a deploy is how a courier is underpaid
  # without anybody noticing.
  #
  # The delivery rows reproduce today's fee exactly, so introducing this table
  # moves no money. See `PricingRate::DEFAULTS` for the arithmetic behind the
  # ride figures and which of his numbers each one targets.
  PricingRate.seed_defaults!
end

seed_section "merchant kinds" do
  # A growable taxonomy, not an enum — Hamma9900 broadened the supply side
  # three times in one hour. A new kind is a row here.
  [
    { slug: "restaurant", name_en: "Restaurant", name_fa: "رستوران",      name_ps: "رستوران",        position: 0 },
    { slug: "bakery",     name_en: "Bakery",     name_fa: "نانوایی",      name_ps: "نانوايي",        position: 1 },
    { slug: "store",      name_en: "Store",      name_fa: "دکان",         name_ps: "دوکان",          position: 2 },
    { slug: "pharmacy",   name_en: "Pharmacy",   name_fa: "دواخانه",      name_ps: "دواخانه",        position: 3 },
    { slug: "bookshop",   name_en: "Bookshop",   name_fa: "کتاب‌فروشی",   name_ps: "کتاب پلورنځی",  position: 4 }
  ].each do |attrs|
    MerchantKind.find_or_initialize_by(slug: attrs[:slug]).update!(attrs)
  end
end

seed_section "merchant categories" do
  # The global browse taxonomy — what a customer filters by. Distinct from a
  # merchant's own CatalogCategory, which is its private menu structure.
  #
  # Afghan dishes first, because that is what the first neighbourhood sells.
  [
    { slug: "kabab",      name_en: "Kabab",       name_fa: "کباب",         name_ps: "کباب",          position: 0 },
    { slug: "qabuli",     name_en: "Qabuli Palaw", name_fa: "قابلی پلو",   name_ps: "قابلي پلو",     position: 1 },
    { slug: "mantu",      name_en: "Mantu",       name_fa: "منتو",         name_ps: "منتو",          position: 2 },
    { slug: "ashak",      name_en: "Ashak",       name_fa: "آشک",          name_ps: "آشک",           position: 3 },
    { slug: "bolani",     name_en: "Bolani",      name_fa: "بولانی",       name_ps: "بولاني",        position: 4 },
    { slug: "burger",     name_en: "Burger",      name_fa: "برگر",         name_ps: "برګر",          position: 5 },
    { slug: "pizza",      name_en: "Pizza",       name_fa: "پیتزا",        name_ps: "پیزا",          position: 6 },
    { slug: "fast_food",  name_en: "Fast food",   name_fa: "فست فود",      name_ps: "فاسټ فوډ",     position: 7 },
    { slug: "sweets",     name_en: "Sweets",      name_fa: "شیرینی",       name_ps: "خواږه",         position: 8 },
    { slug: "drinks",     name_en: "Drinks",      name_fa: "نوشیدنی",      name_ps: "څښاک",          position: 9 },
    { slug: "bread",      name_en: "Bread",       name_fa: "نان",          name_ps: "ډوډۍ",          position: 10 },
    { slug: "grocery",    name_en: "Grocery",     name_fa: "مواد خوراکی",  name_ps: "خوراکي توکي",  position: 11 },
    { slug: "medicine",   name_en: "Medicine",    name_fa: "دوا",          name_ps: "درمل",          position: 12 },
    { slug: "books",      name_en: "Books",       name_fa: "کتاب",         name_ps: "کتابونه",       position: 13 }
  ].each do |attrs|
    MerchantCategory.find_or_initialize_by(slug: attrs[:slug]).update!(attrs)
  end
end

seed_section "search text" do
  # Built AFTER the rows exist, because `search_text` is derived from names and
  # a freshly-seeded database would otherwise have rows nothing can find. Cheap
  # and idempotent: it recomputes the same value from the same name.
  #
  # Also the rebuild to run after any change to Search::TermDictionary.
  Merchant.rebuild_search_text!
  CatalogItem.rebuild_search_text!
end
