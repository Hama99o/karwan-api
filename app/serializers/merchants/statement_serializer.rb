module Merchants
  # A period's earnings, exactly as they were recorded when the statement was
  # issued. R19: "sales, commission deducted, net received."
  class StatementSerializer < ApplicationSerializer
    identifier :id

    fields :period_start, :period_end, :currency, :orders_count, :issued_at

    # ── THE THREE FIGURES, NAMED AS THE SHOP THINKS OF THEM ─────────────────
    #
    # `items_total` is what their food sold for — NOT the customer total, which
    # includes a delivery fee that was never theirs. Sending the customer total
    # here would overstate a shop's sales by the whole delivery line.
    fields :items_total, :commission, :net_received

    # Stated rather than left for the client to derive, because the arithmetic
    # is the shop's main question and a client computing it could disagree with
    # the stored figures — which is precisely what a snapshot exists to prevent.
    field :reconciles do |statement|
      statement.reconciles?
    end
  end
end
