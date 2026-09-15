# Typo- and transliteration-tolerant matching on one column.
#
# This exists because of how this market actually types: "kabab" / "kebab" /
# "kabob" are one food, Pashto and Dari transliterate into Latin differently per
# person, and nobody spells "Shar-e-Naw" the same way twice. English stemming
# does nothing for any of that.
#
# Used as a FALLBACK, not a replacement: exact substring matching is what people
# expect when they type a full word, and similarity ranking is what saves them
# when they do not. `search` (substring, multi-word) runs first; `fuzzy` catches
# what it misses.
module TrigramSearchable
  extend ActiveSupport::Concern

  # `word_similarity`, NOT `similarity`. This was a real bug: `similarity()`
  # compares the query against the WHOLE column value, so "kebab" against
  # "Kabab House" scores about 0.15 — below any threshold you would dare set —
  # and the fuzzy fallback returned nothing for exactly the queries it existed
  # to catch. `word_similarity(query, column)` scores the query against the best
  # matching extent within the column, which is what a person searching a shop
  # name actually means.
  #
  # Threshold MEASURED against "Kabab House", not guessed — the first two
  # guesses (0.2 with `similarity`, then 0.4 with `word_similarity`) both failed
  # the only cases that matter:
  #
  #   query         similarity   word_similarity
  #   kabab           0.500          1.000
  #   kebab           0.200          0.333   <- must match
  #   kabob           0.200          0.500   <- must match
  #   pharmacy        0.000          0.000   <- must not
  #   pizza           0.000          0.000   <- must not
  #
  # 0.3 sits under "kebab" at 0.333 and far above unrelated terms at 0. The gap
  # between the two groups is wide, so this is not a fragile number — but it is
  # an empirical one, and re-tune it by re-running that query rather than by
  # reasoning about trigrams.
  SIMILARITY_THRESHOLD = 0.3

  class_methods do
    def fuzzy_on(column, query, threshold: SIMILARITY_THRESHOLD)
      return none if query.blank?

      where("word_similarity(:q, #{quoted_column(column)}) > :threshold", q: query.to_s, threshold: threshold)
        .order(Arel.sql(sanitize_sql_array([ "word_similarity(?, #{quoted_column(column)}) DESC", query.to_s ])))
    end

    private

    # The column name comes from our own code, never from params, but it is
    # interpolated into SQL — so it is validated against the real column list
    # rather than trusted. A typo here would otherwise be an injection-shaped
    # hole waiting for the first person who wires it to a query string.
    def quoted_column(column)
      name = column.to_s
      raise ArgumentError, "#{name.inspect} is not a column of #{table_name}" unless column_names.include?(name)

      "#{connection.quote_table_name(table_name)}.#{connection.quote_column_name(name)}"
    end
  end
end
