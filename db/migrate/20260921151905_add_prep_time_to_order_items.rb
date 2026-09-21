# HOW LONG THIS DISH TAKES, AS THE MENU SAID AT ORDER TIME.
#
# `catalog_items.prep_time_minutes` has existed since the menu was built, and
# `CatalogItem#effective_prep_time_minutes` — the item's own time, else the
# merchant's — is already SERVED to a browsing customer. But
# `Orders::ArrivalWindow` computes its kitchen leg from
# `merchant.effective_prep_time_minutes` alone, so:
#
#   the customer reads "45 minutes" on the dish, orders it, and is promised a
#   window built from the shop's default of 20.
#
# Two numbers for one dish, in one app, and the promise is the optimistic one.
#
# ── SNAPSHOT, LIKE THE NAME AND THE PRICE BESIDE IT ───────────────────────
#
# One-way door 1: `order_items` stores what things were at order time and a
# historical order is never joined to live menu rows. A merchant raising a
# dish's prep time must not retroactively change what a past customer was
# promised — and reading it live would do exactly that.
#
# Nullable: an order line for something with no prep time (a book, a bottle of
# oil) has none, and `0` would be a claim rather than an absence.
class AddPrepTimeToOrderItems < ActiveRecord::Migration[8.1]
  def change
    add_column :order_items, :prep_time_minutes, :integer
  end
end
