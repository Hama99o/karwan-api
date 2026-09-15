class AddSearchText < ActiveRecord::Migration[8.1]
  # Cross-script search.
  #
  # A customer typing `kabab` could not find کباب, and the failure mode is the
  # worst kind: the app looks EMPTY rather than broken. The user sees nothing,
  # concludes there are no restaurants, and nobody ever reports it — so a
  # customer acquired by a personal conversation is lost silently.
  #
  # This column holds every form of a name somebody might type: the original,
  # every curated dictionary equivalent, and romanisations of any Arabic-script
  # words. See Searchable for why it is stored rather than transliterated at
  # query time.
  def change
    add_column :merchants, :search_text, :text
    add_column :catalog_items, :search_text, :text

    # Trigram, like the existing name indexes — so a typo or a different
    # transliteration still matches within the column.
    add_index :merchants, :search_text, using: :gin, opclass: :gin_trgm_ops,
                                        name: "index_merchants_on_search_text_trgm"
    add_index :catalog_items, :search_text, using: :gin, opclass: :gin_trgm_ops,
                                            name: "index_catalog_items_on_search_text_trgm"
  end
end
