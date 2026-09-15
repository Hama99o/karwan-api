module Customer
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

    # The number that matters. Named for what the customer does with it rather
    # than for the column it comes from.
    field :amount_to_pay_in_cash do |order|
      order.customer_total
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
            # Snapshot names, not live joins — a merchant renaming "Large"
            # tomorrow must not rewrite what somebody ordered today.
            options: item.selected_options.map do |option|
              { option_name: option.option_name, value_name: option.value_name,
                price_delta: option.price_delta }
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
