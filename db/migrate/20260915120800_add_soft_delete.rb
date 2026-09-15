class AddSoftDelete < ActiveRecord::Migration[8.1]
  # One-way door #6 from CLAUDE.md: soft delete, never hard, for anything that
  # can appear in order history. A deleted record with live order history is a
  # hole in the books — an order whose merchant, rider, or menu item has
  # vanished cannot be explained to the person asking about it.
  #
  # Partial indexes, because every read path filters on `deleted_at IS NULL`
  # and indexing the discarded rows buys nothing.
  TABLES = %i[users merchants catalog_categories catalog_items addresses].freeze

  def change
    TABLES.each do |table|
      add_column table, :deleted_at, :datetime
      add_index  table, :deleted_at, where: "deleted_at IS NULL",
                                     name: "index_#{table}_on_kept"
    end
  end
end
