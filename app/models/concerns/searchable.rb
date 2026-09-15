# Maintains a `search_text` column holding every form of a row's name a person
# might type.
#
# ── WHY A STORED COLUMN RATHER THAN TRANSLITERATING THE QUERY ─────────────
# Both were considered. The stored column wins on three counts:
#
#   * IT WORKS IN BOTH DIRECTIONS FROM ONE INDEX. Transliterating the query
#     only bridges Latin→script; a customer typing کباب against a merchant
#     called "Kabab House" still finds nothing unless the index also carries
#     the script form. Storing both means either script matches.
#   * QUERY TIME IS UNCHANGED. One GIN trigram index on one column, the same
#     cost as searching `name` today. Transliterating at query time multiplies
#     every search into several.
#   * LATIN→SCRIPT IS AMBIGUOUS AND SCRIPT→LATIN IS NOT. Romanising once at
#     write time is the direction that has a defensible answer.
#
# The cost is a wider row and a rebuild when the dictionary changes. Both are
# cheap: the column is short and the rebuild is a rake task over a table that
# will hold hundreds of rows in v0, not millions.
module Searchable
  extend ActiveSupport::Concern

  included do
    before_save :rebuild_search_text, if: :should_rebuild_search_text?
  end

  class_methods do
    # The fields whose contents go into the search column. Override where a row
    # has more than one useful name.
    def searchable_fields
      [ :name ]
    end

    # For after a dictionary change: `Merchant.rebuild_search_text!`
    def rebuild_search_text!
      unscoped.find_each { |record| record.update_columns(search_text: record.send(:computed_search_text)) }
    end
  end

  private

  def should_rebuild_search_text?
    search_text.blank? || self.class.searchable_fields.any? { |f| will_save_change_to_attribute?(f) }
  end

  def rebuild_search_text
    self.search_text = computed_search_text
  end

  # The original text, plus every dictionary equivalent, plus romanisations of
  # any Arabic-script words. Deduplicated and space-joined, because trigram
  # matching does not care about structure — only about the characters being
  # present somewhere in the column.
  def computed_search_text
    sources = self.class.searchable_fields.map { |field| send(field) }.compact_blank
    return nil if sources.empty?

    forms = sources.dup
    sources.each do |text|
      forms.concat(Search::TermDictionary.expansions_for(text))
      # Romanise word by word rather than whole-string, so a mixed name like
      # "Kabab کباب House" contributes both halves.
      text.split(/\s+/).each { |word| forms.concat(Search::Transliteration.romanisations(word)) }
    end

    forms.map { |f| f.to_s.strip.downcase }.reject(&:blank?).uniq.join(" ")
  end
end
