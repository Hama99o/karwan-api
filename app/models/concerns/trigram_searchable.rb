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

  # Tuned low on purpose. 0.3 is Postgres' default and it drops "kabob" against
  # "kabab"; the cost of a looser threshold here is an extra result, and the
  # cost of a tighter one is a customer concluding we do not sell the dish.
  SIMILARITY_THRESHOLD = 0.2

  class_methods do
    def fuzzy_on(column, query, threshold: SIMILARITY_THRESHOLD)
      return none if query.blank?

      where("similarity(#{quoted_column(column)}, :q) > :threshold", q: query.to_s, threshold: threshold)
        .order(Arel.sql(sanitize_sql_array([ "similarity(#{quoted_column(column)}, ?) DESC", query.to_s ])))
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
