require "rails_helper"

RSpec.describe Merchant, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:phone) }

    it "rejects a commission rate outside 0..1, which would be a percentage typo" do
      expect(build(:merchant, commission_rate: 1.5)).not_to be_valid
      expect(build(:merchant, commission_rate: -0.1)).not_to be_valid
      expect(build(:merchant, commission_rate: 0.125)).to be_valid
    end

    it "rejects a zero prep time but allows none at all" do
      expect(build(:merchant, prep_time_minutes: 0)).not_to be_valid
      expect(build(:merchant, prep_time_minutes: nil)).to be_valid
    end
  end

  describe "#merchant_kind" do
    # A table, not an enum: the supply side was broadened twice in one hour, so
    # a new kind must be a row rather than a migration.
    it "takes its kind from a growable table" do
      bookshop = create(:merchant_kind, :bookshop)
      merchant = create(:merchant, merchant_kind: bookshop)

      expect(merchant.merchant_kind.slug).to eq("bookshop")
      expect(merchant.merchant_kind.name_for(:fa)).to eq("کتاب‌فروشی")
    end

    it "requires one, because an uncategorised merchant cannot be browsed to" do
      expect(build(:merchant, merchant_kind: nil)).not_to be_valid
    end
  end

  describe "#effective_prep_time_minutes" do
    # A book has no preparation time and must not inherit a kitchen's.
    it "is the merchant's own time for a food merchant" do
      expect(create(:merchant, prep_time_minutes: 25).effective_prep_time_minutes).to eq(25)
    end

    it "is nil for a merchant that does not prepare food" do
      expect(create(:merchant, :store).effective_prep_time_minutes).to be_nil
    end

    it "does not invent a prep time when none was given" do
      expect(create(:merchant, prep_time_minutes: nil).effective_prep_time_minutes).to be_nil
    end
  end

  describe "#accepting_orders?" do
    # `is_open` is a MANUAL toggle and is the authority. A merchant marked open
    # that isn't is the most damaging state in the system, which is why it
    # defaults to closed and why opening hours cannot override it either way.
    it "is true only when kept, active and manually open" do
      expect(create(:merchant)).to be_accepting_orders
    end

    it "is false when manually closed" do
      expect(create(:merchant, :closed)).not_to be_accepting_orders
    end

    it "is false when not yet approved" do
      expect(create(:merchant, :pending)).not_to be_accepting_orders
    end

    it "is false when suspended" do
      expect(create(:merchant, :suspended)).not_to be_accepting_orders
    end

    it "is false once discarded" do
      merchant = create(:merchant)
      merchant.discard!

      expect(merchant).not_to be_accepting_orders
    end

    # Opening hours are advisory: they tell a customer when to come back. A
    # merchant open late must not be shut by a schedule row.
    it "is not overridden by opening hours" do
      merchant = create(:merchant, is_open: true)
      create(:merchant_opening_hour, merchant: merchant, day_of_week: 0,
                                     opens_at: "09:00", closes_at: "10:00")

      expect(merchant.reload).to be_accepting_orders
    end
  end

  describe "#commission_on" do
    it "takes the merchant's own rate, rounded to the minor unit" do
      merchant = build(:merchant, commission_rate: 0.125)

      expect(merchant.commission_on(400)).to eq(50)
      expect(merchant.commission_on(333)).to eq(BigDecimal("41.63"))
    end
  end

  describe ".search" do
    let!(:kabab_house) { create(:merchant, name: "Shar-e-Naw Kabab House") }
    let!(:pizza_place) { create(:merchant, name: "Kabul Pizza Corner") }

    it "matches on the merchant's own name" do
      expect(described_class.search("kabab")).to contain_exactly(kabab_house)
    end

    it "is case-insensitive" do
      expect(described_class.search("KABAB")).to contain_exactly(kabab_house)
    end

    # People search for a DISH, not a shop. "mantu" is food, not a business.
    it "matches a merchant by the name of an available item it sells" do
      category = create(:catalog_category, merchant: pizza_place)
      create(:catalog_item, catalog_category: category, name: "Mantu")

      expect(described_class.search("mantu")).to contain_exactly(pizza_place)
    end

    it "ignores a sold-out item, which cannot be ordered" do
      category = create(:catalog_category, merchant: pizza_place)
      create(:catalog_item, :sold_out, catalog_category: category, name: "Mantu")

      expect(described_class.search("mantu")).to be_empty
    end

    it "ignores a discarded item" do
      category = create(:catalog_category, merchant: pizza_place)
      create(:catalog_item, :discarded, catalog_category: category, name: "Mantu")

      expect(described_class.search("mantu")).to be_empty
    end

    # The Dari query now ALSO finds "Shar-e-Naw Kabab House", which is the
    # cross-script feature working rather than a regression: the dictionary puts
    # کباب into that merchant's search text because its Latin name contains
    # "Kabab". Before, a Dari-speaking customer searching کباب would have missed
    # a kabab house entirely — the exact silent emptiness the feature exists to
    # prevent.
    it "matches on a merchant category, in any of the three locales" do
      category = create(:merchant_category, :kabab)
      create(:merchant_category_assignment, merchant: pizza_place, merchant_category: category)

      expect(described_class.search("kabab")).to contain_exactly(kabab_house, pizza_place)
      expect(described_class.search("کباب")).to contain_exactly(kabab_house, pizza_place)
    end

    # Each word narrows, and each word may match any of the three sources. This
    # is what makes "kabul pizza" behave the way a person expects.
    it "narrows on every word of a multi-word query" do
      expect(described_class.search("kabul pizza")).to contain_exactly(pizza_place)
      expect(described_class.search("kabul kabab")).to be_empty
    end

    # EXISTS subqueries rather than joins, so a merchant with four matching
    # dishes appears once, not four times.
    it "returns a merchant once even when several of its items match" do
      category = create(:catalog_category, merchant: pizza_place)
      create(:catalog_item, catalog_category: category, name: "Pizza Margherita")
      create(:catalog_item, catalog_category: category, name: "Pizza Pepperoni")
      create(:catalog_item, catalog_category: category, name: "Pizza Special")

      expect(described_class.search("pizza").to_a.size).to eq(1)
    end

    it "returns everything for a blank query rather than nothing" do
      expect(described_class.search("")).to include(kabab_house, pizza_place)
      expect(described_class.search(nil)).to include(kabab_house, pizza_place)
    end
  end

  describe ".fuzzy" do
    let!(:kabab_house) { create(:merchant, name: "Kabab House") }

    # The reason pg_trgm is here rather than tsvector: "kabab", "kebab" and
    # "kabob" are one food, and Pashto/Dari transliterate into Latin
    # differently per person. English stemming does nothing for that.
    it "finds a merchant through a different transliteration" do
      expect(described_class.fuzzy("kebab")).to include(kabab_house)
      expect(described_class.fuzzy("kabob")).to include(kabab_house)
    end

    it "returns nothing for a blank query rather than everything" do
      expect(described_class.fuzzy("")).to be_empty
    end

    it "does not match an unrelated name" do
      expect(described_class.fuzzy("pharmacy")).not_to include(kabab_house)
    end
  end

  describe ".orderable" do
    it "is only kept, active, manually-open merchants" do
      open_merchant = create(:merchant)
      create(:merchant, :closed)
      create(:merchant, :pending)
      create(:merchant).discard!

      expect(described_class.orderable).to contain_exactly(open_merchant)
    end
  end

  describe "#discard!" do
    # A merchant that is gone must not leave an orderable catalog behind.
    it "cascades to its catalog" do
      merchant = create(:merchant, :with_menu)
      merchant.discard!

      expect(merchant.catalog_items.kept).to be_empty
      expect(merchant.catalog_categories.kept).to be_empty
      expect(CatalogItem.discarded.count).to eq(1)
    end

    it "refuses to hard-destroy a merchant with order history" do
      order = create(:order)

      expect(order.merchant.destroy).to be false
    end
  end

  # ── ONE NOTION OF "OPEN", ACROSS ALL FOUR COMBINATIONS ────────────────────
  #
  # The model has two: the shopkeeper's toggle, which it names the authority
  # twice, and the posted week. `next_opens_at` asked the week while
  # `accepting_orders?` asked the toggle, so one card could carry both "open
  # now" and "opens at 08:00". Only the second row below changed; the table is
  # here so the next change to either notion has to face all four at once.
  describe "#next_opens_at" do
    let(:shop) { create(:merchant, is_open: true) }

    before do
      MerchantOpeningHour::DAYS.each do |day|
        create(:merchant_opening_hour, merchant: shop, day_of_week: day,
                                       opens_at: "08:00", closes_at: "22:00")
      end
    end

    it "says nothing when the shop is open and inside its week" do
      travel_to Time.zone.parse("2026-09-18 12:00") do
        expect(shop.reload.accepting_orders?).to be(true)
        expect(shop.next_opens_at).to be_nil
      end
    end

    # THE ONE THAT WAS WRONG. A shop left toggled on overnight.
    it "says nothing when the shop is open and its week says otherwise" do
      travel_to Time.zone.parse("2026-09-18 03:00") do
        expect(shop.reload.accepting_orders?).to be(true)
        expect(shop.next_opens_at).to be_nil,
                                      "a shop that is taking orders has no next opening; the card would say both"
      end
    end

    # Unchanged and deliberate: the schedule cannot know when a shopkeeper who
    # shut early will come back, and "tomorrow at 08:00" is a worse answer than
    # none.
    it "says nothing when the shop shut early inside its own week" do
      shop.update!(is_open: false)

      travel_to Time.zone.parse("2026-09-18 12:00") do
        expect(shop.reload.next_opens_at).to be_nil
      end
    end

    it "gives the next opening only when the shop is shut and its week agrees" do
      shop.update!(is_open: false)

      travel_to Time.zone.parse("2026-09-18 06:00") do
        expect(shop.reload.next_opens_at.strftime("%H:%M")).to eq("08:00")
      end
    end

    it "says nothing at all when no week has been given" do
      shop.opening_hours.destroy_all

      expect(shop.reload.next_opens_at).to be_nil
      expect(shop.hours_known?).to be(false)
    end
  end

  # ── THE STANDARD RATE, WHICH WAS A DEAD ROW ON THE CONFIG SCREEN ──────────
  #
  # CLAUDE.md asks for both a per-restaurant commission rate AND commission % as
  # an admin-editable setting that "gets tuned weekly". It was neither: the
  # column is `null: false` with a DATABASE default, so a new shop took 0.125
  # from the schema and `Setting.fetch("commission_rate")` was called by nothing
  # in the whole app. Hamma9900 could set that row to 0.20 and every shop he
  # onboarded afterwards would still be at 0.125.
  describe "the standard commission rate" do
    # Built without the factory's `commission_rate`, which states 0.125
    # explicitly — and an explicit value is exactly what this callback must not
    # override. Using the factory here would test nothing.
    def onboard(attrs = {})
      described_class.create!({ name: "Shop #{SecureRandom.hex(3)}", phone: "+9370#{rand(1_000_000..9_999_999)}",
                                latitude: 34.5, longitude: 69.2,
                                merchant_kind: MerchantKind.first || create(:merchant_kind) }.merge(attrs))
    end

    def standard!(value)
      Setting.find_or_initialize_by(key: "commission_rate").update!(value: value, value_type: :decimal)
    end

    it "onboards a new shop at the standard, not at the schema's default" do
      standard!("0.2")

      shop = onboard

      expect(shop.commission_rate).to eq(BigDecimal("0.2")),
                                      "the shop took the database default, so the Config screen changes nothing"
    end

    # ── THE PATH THIS EXISTS FOR, AND IT WAS DEAD ────────────────────────
    #
    # The ops console's new-merchant form carried a `commission_rate` field
    # pre-filled from the column default, so every console onboarding "supplied"
    # a rate and the standard never applied. Found on the rig, not here — the
    # earlier examples all passed because they never sent a blank field.
    #
    # An empty number input submits "", which is what this plants.
    it "applies the standard when the console form is left blank" do
      standard!("0.2")

      shop = onboard(commission_rate: "")

      expect(shop.commission_rate).to eq(BigDecimal("0.2")),
                                      "a blank field counts as a supplied rate, so the standard is skipped"
    end

    # And the reason the blank case exists at all: nothing may put the column
    # default back, because the form reads it and submits it.
    it "has no column default competing with the standard" do
      expect(described_class.columns_hash["commission_rate"].default).to be_nil,
                                                                        "the schema default is back — the console " \
                                                                        "form will pre-fill and submit it, and the " \
                                                                        "standard will never apply again"
      expect(described_class.new.commission_rate).to be_nil
    end

    it "leaves a shop onboarded at its own negotiated rate alone" do
      standard!("0.2")

      shop = onboard(commission_rate: 0.08)

      expect(shop.commission_rate).to eq(BigDecimal("0.08"))
    end

    # ON CREATE ONLY, and this is the half that matters. A shop's rate is what
    # it agreed to. Re-reading the setting later would let one edit rewrite what
    # every existing shop is paid, retroactively — the shape one-way door 1
    # exists to prevent.
    it "never rewrites what an existing shop already agreed to" do
      shop = onboard
      before = shop.commission_rate

      standard!("0.4")
      shop.update!(name: "Existing, renamed")

      expect(shop.reload.commission_rate).to eq(before),
                                             "raising the standard has changed what an existing shop is paid"
    end

    # The validation runs AFTER the callback, so a standard nobody can honour is
    # refused at the merchant rather than stored and discovered on an order.
    it "refuses to onboard against an impossible standard" do
      standard!("1.5")

      shop = described_class.new(name: "Impossible", phone: "+93700001237", latitude: 34.5, longitude: 69.2,
                                 merchant_kind: MerchantKind.first || create(:merchant_kind))

      expect(shop).not_to be_valid
      expect(shop.errors[:commission_rate]).to be_present
    end
  end
end
