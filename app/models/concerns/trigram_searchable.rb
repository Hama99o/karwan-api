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
    # Ranked by closeness, loosest match first in the WHERE and best match first
    # in the ORDER BY.
    #
    # Built with Arel rather than an interpolated SQL string. The previous
    # version validated the column against `column_names` and quoted it, which
    # was genuinely safe — but brakeman flagged it as a possible SQL injection
    # (exit 3, so CI went red) and it was right to: a human reading
    # `"...#{quoted_column(column)}..."` cannot tell the guard exists without
    # following the method, and the guard is one careless edit from being
    # dropped. Arel takes the column as an identifier, not as text, so there is
    # no string to get wrong and nothing to audit.
    def fuzzy_on(column, query, threshold: SIMILARITY_THRESHOLD)
      return none if query.blank?

      score = word_similarity_score(column, query)

      where(score.gt(threshold)).order(Arel::Nodes::Descending.new(score))
    end

    private

    # word_similarity(:query, "table"."column") as an Arel node.
    #
    # Argument order matters and is easy to get backwards: word_similarity(a, b)
    # scores `a` against the best matching extent within `b`, so the QUERY goes
    # first and the column second. Reversed, it scores the whole column value
    # against the query and behaves like plain `similarity()` — which is the bug
    # this concern was rewritten to fix.
    def word_similarity_score(column, query)
      Arel::Nodes::NamedFunction.new(
        "word_similarity",
        [ Arel::Nodes.build_quoted(query.to_s), arel_attribute_for(column) ]
      )
    end

    # The column name always comes from our own code, never from params, but it
    # is still checked against the real column list: a typo would otherwise
    # produce a confusing Postgres error at runtime instead of a clear one here.
    def arel_attribute_for(column)
      name = column.to_s
      raise ArgumentError, "#{name.inspect} is not a column of #{table_name}" unless column_names.include?(name)

      arel_table[name]
    end
  end
end
