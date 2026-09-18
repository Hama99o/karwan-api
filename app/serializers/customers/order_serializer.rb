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

      # ── THE NUMBER A CUSTOMER ACTUALLY RINGS ────────────────────────────────
      #
      # The call that gets made: an item is wrong, the order is late, the courier
      # cannot find the gate. `merchant_id` and `merchant_name` were here and
      # nothing to dial, so the app's contact sheet had a merchant row with no
      # number — and fetching the merchant separately to fill one row is what
      # correction 17 forbids.
      #
      # `phone` AND NOT `contact_person_phone`, which are different things: one is
      # the shop, the other is a named human. A customer ringing about a kebab
      # wants whoever picks up at the shop; the office ringing about a payout
      # wants the person. `contact_person_phone` stays on the merchant profile,
      # which is an operator surface.
      #
      # NIL ONCE THE ORDER IS TERMINAL. A number on a delivered order from three
      # weeks ago is a customer ringing a restaurant about something nobody there
      # remembers — and the shop pays for that call in patience. The app already
      # branches on `is_live`; this agrees with it rather than asking the client to
      # enforce it.
      field :merchant_phone do |order|
        order.merchant.phone if !order.terminal? && order.merchant
      end

      # ── HOW THE FARE WAS MEASURED, AND WHETHER THE PIN IS REACHABLE ──────
      #
      # `docs/design/customer/order-tracking/SPEC.md` names both and the payload
      # carried neither, so the tracking screen was blocked on the API. Found by
      # pointing the serializer sweep at the design rather than at the code.
      #
      # Both are read from what was FROZEN on this order at quote time — the
      # stored `distance_source` and the stored snap distances — never
      # recomputed. MAP_AND_ROUTING.md requires a fare be explainable later, and
      # road pricing and crow-flight pricing differ by 15-20%; an explanation
      # that re-measures is not an explanation of what was charged.
      fields :distance_source

      # The copy for this already exists in the app — "a courier may not find
      # this from the pin alone" — and has never been wired to a signal. An
      # airport pin snapped 548.9 m to the road network in the measurement that
      # motivated it.
      field :pin_far_from_road do |order|
        order.pin_far_from_road?
      end

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
            #
            # THIS COMMENT WAS A PROMISE THE CODE DID NOT KEEP. It served the
            # raw foreign key, which survives a soft delete — so a discarded
            # dish still handed the app a pointer that LOOKS usable and can
            # never resolve, because `CartResolver` looks in `catalog_items.kept`.
            # The difference on a screen is a greyed "order again" versus a
            # button that fails when tapped.
            #
            # The snapshot beside it is untouched: one-way door 1 means the
            # history still reads "Chicken Kabab, 400" after the dish is gone.
            # Only the pointer goes.
            catalog_item_id: (item.catalog_item_id if item.catalog_item&.kept?),
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
