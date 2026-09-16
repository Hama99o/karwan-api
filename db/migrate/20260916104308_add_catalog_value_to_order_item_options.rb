# WHICH option value was chosen, so a past order can be re-ordered.
#
# ── The snapshot stays the receipt. This is not a replacement for it ──────
# One-way door #1: `order_items` and `order_item_options` store the name, the
# price and the chosen options AS THEY WERE at order time, never a live join.
# A restaurant renaming "Large" tomorrow must not rewrite what somebody
# ordered today. That rule does not change here — `option_name`, `value_name`
# and `price_delta` remain the authoritative record of what was bought and for
# how much.
#
# ── What it is FOR ───────────────────────────────────────────────────────
# PRODUCT.md asks for order history "itemised, re-orderable".
# `order_items.catalog_item_id` already exists, so the DISH can be found on
# today's menu. The chosen option VALUES could not be: with only names, a dish
# carrying a required option could not be re-added to a cart at all.
#
# So this column is used for exactly one thing — resolving "order this again"
# against the live catalog — and never for displaying or totalling a past
# order.
#
# ── Why it is safe ───────────────────────────────────────────────────────
# Additive and NULLABLE. No existing column changes meaning, no row is
# rewritten, and every order placed before today simply has it empty — for
# which the re-order path falls back to matching by name and, failing that,
# asks the customer to choose again. `Orders::CartResolver` re-validates
# availability and price at the moment of re-ordering, so a delisted or
# sold-out value is refused exactly like any other bad cart line.
#
# `on_delete: :nullify` rather than restrict: a merchant deleting an option
# value must not be blocked by, or cascade into, a historical order. The
# receipt survives; only the re-order shortcut is lost.
#
# Approved by Hamma9900 directly (16 Sept 2026) when the alternatives were put
# to him: match by name, which breaks silently the day a value is renamed, or
# ship history without re-order.
class AddCatalogValueToOrderItemOptions < ActiveRecord::Migration[8.1]
  def change
    add_reference :order_item_options, :catalog_item_option_value,
                  null: true,
                  foreign_key: { to_table: :catalog_item_option_values, on_delete: :nullify },
                  index: true
  end
end
