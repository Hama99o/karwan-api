# Reference data. Every environment, idempotent, safe after a deploy.

seed_section "settings" do
  # Refreshes descriptions and currencies (ours) without overwriting values an
  # admin has tuned (theirs). Asserted by a spec, because silently resetting
  # the delivery fee on a deploy is the kind of bug nobody notices until a
  # courier is underpaid.
  Setting.seed_defaults!
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
