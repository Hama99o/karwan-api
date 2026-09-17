module Customers
  # An order as the CUSTOMER sees it.
  #
  # What is deliberately absent: the commission, the merchant payout, the
  # courier's fee. The customer's business is what THEY pay. Showing them our
  # cut invites a conversation nobody wants at the door, and showing the
  # courier's fee invites haggling over it.
  #
  # What is deliberately prominent: `amount_to_pay_in_cash`. PRODUCT.md is
  # explicit that this is shown large, because the whole model rests on somebody
  # having the right notes in their hand when the courier arrives.
  class OrderSerializer < ApplicationSerializer
    identifier :id

    fields :code, :status, :currency

    field :merchant_name do |order|
      order.merchant.name
    end

    # THE ID, AND IT IS FOR RE-ORDERING. `merchant_name` is what the customer
    # reads; this is what the app needs to open the right catalog when they tap
    # "order this again" — without it the name would have to be searched for,
    # which finds the wrong shop the first time two are called Kabab House.
    #
    # Not sensitive: a customer browses merchants by id all day on
    # `/public/merchants`. It is only absent here because nothing had needed it.
    field :merchant_id do |order|
      order.merchant_id
    end

    # The number that matters. Named for what the customer does with it rather
    # than for the column it comes from.
    field :amount_to_pay_in_cash do |order|
      order.customer_total
    end

    # And what to bring, from the SAME rule the quote uses — so the cart and
    # the status screen cannot advise differently about one order.
    field :suggested_notes do |order|
      Monetary.change_advice(order.customer_total)
    end

    view :list do
      fields :items_total, :delivery_fee, :customer_total, :placed_at

      field :item_count do |order|
        order.order_items.sum(&:quantity)
      end

      field :is_live do |order|
        !order.terminal?
      end
    end

    # HE IS AT THE GATE. The same fact the notification carries, on the screen
    # the app already polls — because push is ONE of three channels and never
    # the channel: a notification can be refused, delayed by OEM power
    # management, or arrive on a phone somebody else is holding.
    #
    # A timestamp rather than a boolean, so the app can say "for four minutes"
    # if it ever wants to, and so the fact survives being read twice.
    field :courier_arrived_at

    view :detailed do
      include_view :list

      fields :delivery_landmark_note, :customer_phone, :notes

      field :delivery_location do |order|
        { latitude: order.delivery_latitude, longitude: order.delivery_longitude }
      end

      field :items do |order|
        order.order_items.map do |item|
          {
            name: item.name, quantity: item.quantity, unit_price: item.unit_price,
            options_total: item.options_total, line_total: item.line_total,
            currency: item.currency, notes: item.notes,
            # FOR RE-ORDERING ONLY. Nil when the dish has since been removed
            # from the menu, which the app must handle rather than assume —
            # `Orders::CartResolver` refuses a delisted or sold-out item at the
            # moment of re-ordering, exactly like any other bad cart line.
            catalog_item_id: item.catalog_item_id,
            # Snapshot names, not live joins — a merchant renaming "Large"
            # tomorrow must not rewrite what somebody ordered today.
            options: item.selected_options.map do |option|
              { option_name: option.option_name, value_name: option.value_name,
                price_delta: option.price_delta,
                # Also re-order only. Nil for every order placed before this
                # column existed, and for a value the merchant has deleted.
                value_id: option.catalog_item_option_value_id }
            end
          }
        end
      end

      # The state machine, shown plainly with a timestamp each, because
      # PRODUCT.md asks for exactly that: waiting for the merchant, preparing,
      # ready, on the way, delivered.
      field :timeline do |order|
        order.transitions.chronological.map do |transition|
          { status: transition.to_status, at: transition.created_at,
            by_system: transition.system? }
        end
      end

      # First name only. The customer needs to know who is knocking, not who
      # the courier is.
      field :courier do |order|
        next nil if order.courier.nil?

        { name: order.courier.display_name.to_s.split.first, phone: order.courier.phone }
      end

      field :can_cancel do |order|
        order.can_transition_to?(:cancelled, actor_role: :customer)
      end
    end
  end
end
