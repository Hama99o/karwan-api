module Customer
  # A price BEFORE the order exists.
  #
  # Correction 4: money is shown before it is owed, at every step, for every
  # role. A customer must see the total before they commit, and it must be the
  # same number they are asked for at the door — so it comes from the same
  # `Pricing::DeliveryQuote` the order itself will use, not from a second
  # formula that can drift.
  class QuoteSerializer < ApplicationSerializer
    fields :distance_km, :duration_minutes, :currency

    field :items_total do |quote|
      quote.amounts[:items_total]
    end

    field :delivery_fee do |quote|
      quote.amounts[:delivery_fee]
    end

    field :amount_to_pay_in_cash do |quote|
      quote.amounts[:customer_total]
    end

    # So the app can warn "you will need change" rather than the courier
    # discovering it on a doorstep. Couriers carry a float, but a 5,000 note
    # for a 500 order is still a problem.
    field :suggested_notes do |quote|
      quote.amounts[:customer_total]
    end
  end
end
