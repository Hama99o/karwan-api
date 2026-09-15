module Merchants
  # An order as the MERCHANT sees it. A ticket for the kitchen, not a receipt.
  #
  # WHAT IS DELIBERATELY ABSENT: the delivery address. The merchant does not
  # deliver — the courier does — so they have no business holding a customer's
  # home location. It is the courier's serializer that carries it, and only
  # once they are assigned. Same record, three shapes; this is why there is no
  # single OrderSerializer with conditionals.
  #
  # What IS prominent: the items, their options, the customer's note, and the
  # AGE. PRODUCT.md asks for age on every card, because an order sitting too
  # long is the thing a busy kitchen stops noticing.
  class OrderSerializer < ApplicationSerializer
    identifier :id

    fields :code, :status, :currency, :notes

    # Minutes in the CURRENT state, not since the order was placed. A ten
    # minute old order that was accepted nine minutes ago is not late; one
    # sitting unaccepted for ten minutes is.
    field :minutes_in_state do |order|
      ((Time.current - order.state_entered_at) / 60).floor
    end

    field :is_overdue do |order|
      order.overdue?
    end

    field :item_count do |order|
      order.order_items.sum(&:quantity)
    end

    view :board do
      fields :placed_at, :accepted_at, :ready_at

      field :items do |order|
        order.order_items.map do |item|
          {
            name: item.name, quantity: item.quantity, notes: item.notes,
            # Options matter more to the kitchen than to anyone else — "no
            # rice, extra chutney" IS the order.
            options: item.selected_options.map { |o| "#{o.option_name}: #{o.value_name}" }
          }
        end
      end
    end

    view :detailed do
      include_view :board

      # What the merchant is paid, in cash, at pickup: the items less our
      # commission. Correction 4 — money is shown before it is owed, so the
      # commission is visible here rather than discovered later.
      fields :items_total, :commission, :merchant_payout

      field :courier do |order|
        next nil if order.courier.nil?

        # The merchant needs to know who is coming to collect and be able to
        # ring them. Not the courier's full identity.
        { name: order.courier.display_name.to_s.split.first, phone: order.courier.phone }
      end

      field :paid_at do |order|
        order.merchant_paid_at
      end
    end
  end
end
