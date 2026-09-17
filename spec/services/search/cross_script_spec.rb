require "rails_helper"

# CROSS-SCRIPT SEARCH.
#
# The failure this prevents is the worst kind available: a customer types
# `kabab`, sees nothing, and concludes there are no restaurants. The app looks
# EMPTY rather than broken, so nobody reports it — and a customer Hamma9900
# acquired by talking to them in person is lost silently.
RSpec.describe "Cross-script search" do
  let(:merchant) { create(:merchant, name: "کباب شهر نو", is_open: true) }
  let(:category) { create(:catalog_category, merchant: merchant) }

  describe "a Latin query finding an Arabic-script name" do
    before { create(:catalog_item, catalog_category: category, name: "کباب مرغ") }

    # The headline case. Every spelling somebody might type.
    %w[kabab kebab kabob kebob].each do |spelling|
      it "finds کباب when the customer types #{spelling}" do
        expect(CatalogItem.available.search(spelling)).not_to be_empty
        expect(Merchant.orderable.search(spelling)).to include(merchant)
      end
    end

    it "finds مرغ when the customer types murgh" do
      expect(CatalogItem.available.search("murgh")).not_to be_empty
    end

    it "finds مرغ when the customer types chicken" do
      expect(CatalogItem.available.search("chicken")).not_to be_empty
    end
  end

  describe "an Arabic-script query finding a Latin name" do
    before { create(:catalog_item, catalog_category: category, name: "Chicken Kabab") }

    # The direction a query-time transliteration would have missed, and the
    # reason the column is stored rather than the query transformed.
    it "finds a Latin-named dish when the customer types کباب" do
      expect(CatalogItem.available.search("کباب")).not_to be_empty
    end

    it "finds it when the customer types مرغ" do
      expect(CatalogItem.available.search("مرغ")).not_to be_empty
    end
  end

  describe "dishes beyond kabab" do
    {
      "مانتو" => %w[mantu manto mantoo],
      "بولانی" => %w[bolani bulani],
      "قابلی پلو" => %w[qabuli qabili palaw],
      "آشک" => %w[ashak aushak],
      "دوغ" => %w[doogh dogh],
      "فرنی" => %w[firni ferni]
    }.each do |script_name, latin_spellings|
      latin_spellings.each do |spelling|
        it "finds #{script_name} from #{spelling}" do
          create(:catalog_item, catalog_category: category, name: script_name)

          expect(CatalogItem.available.search(spelling)).not_to be_empty
        end
      end
    end
  end

  describe "non-food merchants, because a merchant is not only a restaurant" do
    it "finds دواخانه from pharmacy" do
      pharmacy = create(:merchant, name: "دواخانه شفا", is_open: true)

      expect(Merchant.orderable.search("pharmacy")).to include(pharmacy)
    end

    it "finds کتاب from bookshop" do
      shop = create(:merchant, name: "کتاب فروشی دانش", is_open: true)

      expect(Merchant.orderable.search("book")).to include(shop)
    end
  end

  describe "what it must NOT do" do
    before { create(:catalog_item, catalog_category: category, name: "کباب مرغ") }

    # A search that matches everything is as useless as one that matches
    # nothing — it just fails less visibly.
    it "does not match an unrelated query" do
      expect(CatalogItem.available.search("pizza")).to be_empty
      expect(Merchant.orderable.search("pharmacy")).not_to include(merchant)
    end

    it "still narrows on every word of a multi-word query" do
      create(:catalog_item, catalog_category: category, name: "کباب چوپان")

      expect(CatalogItem.available.search("kabab murgh").count).to eq(1)
    end
  end

  describe "the search column itself" do
    it "is rebuilt when the name changes" do
      item = create(:catalog_item, catalog_category: category, name: "Chicken Kabab")
      expect(item.search_text).to include("کباب")

      item.update!(name: "منتو")

      expect(item.reload.search_text).to include("mantu")
      # by-design: the line above asserts "mantu" IS present, so search_text is populated.
      expect(item.search_text).not_to include("kabab")
    end

    it "carries the original name, the dictionary forms and the romanisations" do
      item = create(:catalog_item, catalog_category: category, name: "کباب")

      expect(item.search_text).to include("کباب")   # original
      expect(item.search_text).to include("kabob")   # dictionary
      expect(item.search_text).to include("kbab")    # romanisation
    end

    # After a dictionary change, so existing rows pick up new spellings.
    it "can be rebuilt in bulk" do
      item = create(:catalog_item, catalog_category: category, name: "کباب")
      item.update_columns(search_text: nil)

      CatalogItem.rebuild_search_text!

      expect(item.reload.search_text).to be_present
    end

    it "falls back to the name when the column is empty, so nothing is unfindable" do
      item = create(:catalog_item, catalog_category: category, name: "Special Pizza")
      item.update_columns(search_text: nil)

      expect(CatalogItem.available.search("pizza")).to include(item)
    end
  end

  describe "fuzzy matching across scripts" do
    it "survives a typo in a transliteration" do
      create(:catalog_item, catalog_category: category, name: "کباب")

      expect(CatalogItem.available.fuzzy("kabaab")).not_to be_empty
    end
  end
end
