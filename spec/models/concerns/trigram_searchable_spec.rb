require "rails_helper"

# Exercised through Merchant, which includes the concern. Testing it via a real
# model rather than an anonymous class keeps the SQL honest — the whole point of
# this concern is the SQL it emits.
RSpec.describe TrigramSearchable do
  describe ".fuzzy_on" do
    it "emits word_similarity with the query FIRST and the column second" do
      sql = Merchant.fuzzy("kebab").to_sql

      # Argument order is the bug this concern was rewritten to fix: reversed,
      # word_similarity scores the whole column against the query and behaves
      # like plain similarity(), which failed every transliteration case.
      expect(sql).to include(%{word_similarity('kebab', "merchants"."name")})
      expect(sql).to include("DESC")
    end

    # The previous implementation interpolated the column into a SQL string.
    # It was guarded and safe, but brakeman flagged it (exit 3, CI red) and a
    # reader could not see the guard without following the method.
    it "quotes the column as an identifier rather than interpolating it" do
      expect(Merchant.fuzzy("kebab").to_sql).to include(%{"merchants"."name"})
    end

    it "uses the measured threshold" do
      expect(Merchant.fuzzy("kebab").to_sql).to include("> #{TrigramSearchable::SIMILARITY_THRESHOLD}")
    end

    # The column always comes from our own code, never from params — but a typo
    # should fail here with a clear message rather than as a confusing Postgres
    # error at runtime.
    it "raises on a column the model does not have" do
      expect { Merchant.fuzzy_on(:not_a_column, "kebab") }
        .to raise_error(ArgumentError, /not a column of merchants/)
    end

    it "returns nothing for a blank query rather than everything" do
      create(:merchant, name: "Kabab House")

      expect(Merchant.fuzzy_on(:name, "")).to be_empty
      expect(Merchant.fuzzy_on(:name, nil)).to be_empty
    end

    it "orders the closest spelling first" do
      exact = create(:merchant, name: "Kabab")
      looser = create(:merchant, name: "Kabab House Number Two")

      results = Merchant.fuzzy("kabab").to_a

      expect(results).to include(exact, looser)
      expect(results.first).to eq(exact)
    end
  end
end
